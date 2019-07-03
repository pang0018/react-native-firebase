/**
 * Copyright (c) 2016-present Invertase Limited & Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this library except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import <React/RCTUtils.h>

#import "RNFBRCTEventEmitter.h"
#import "RNFBFirestoreCollectionModule.h"

static __strong NSMutableDictionary *collectionSnapshotListeners;
static NSString *const RNFB_FIRESTORE_COLLECTION_SYNC = @"firestore_collection_sync_event";

@implementation RNFBFirestoreCollectionModule
#pragma mark -
#pragma mark Module Setup

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue {
  return dispatch_queue_create("io.invertase.firebase.firestore", DISPATCH_QUEUE_SERIAL);
}

- (id)init {
  self = [super init];
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    collectionSnapshotListeners = [[NSMutableDictionary alloc] init];
  });
  return self;
}

- (void)dealloc {
  [self invalidate];
}

- (void)invalidate {
  for (NSString *listenerId in collectionSnapshotListeners) {
    id <FIRListenerRegistration> listener = collectionSnapshotListeners[listenerId];
    [listener remove];
    [collectionSnapshotListeners removeObjectForKey:listenerId];
  }
}

#pragma mark -
#pragma mark Firebase Firestore Methods

RCT_EXPORT_METHOD(collectionOnSnapshot:
  (FIRApp *) firebaseApp
    :(NSString *)path
    :(NSString *)type
    :(NSArray *)filters
    :(NSArray *)orders
    :(NSDictionary *)options
    :(NSString *)listenerId
    :(NSDictionary *)listenerOptions
) {
  if (collectionSnapshotListeners[listenerId]) {
    return;
  }

  FIRFirestore *firestore = [RNFBFirestoreCommon getFirestoreForApp:firebaseApp];
  FIRQuery *query = [RNFBFirestoreCommon getQueryForFirestore:firestore path:path type:type];

  RNFBFirestoreQuery *firestoreQuery = [[RNFBFirestoreQuery alloc] initWithModifiers:firestore query:query filters:filters orders:orders options:options];

  __weak RNFBFirestoreCollectionModule *weakSelf = self;
  id listenerBlock = ^(FIRQuerySnapshot *snapshot, NSError *error) {
    if (error) {
      id <FIRListenerRegistration> listener = collectionSnapshotListeners[listenerId];
      if (listener) {
        [listener remove];
        [collectionSnapshotListeners removeObjectForKey:listenerId];
      }
      [weakSelf sendSnapshotError:firebaseApp error:error];
    } else {
      [weakSelf sendSnapshotEvent:firebaseApp snapshot:snapshot];
    }
  };

  BOOL includeMetadataChanges = NO;
  if (listenerOptions[KEY_INCLUDE_METADATA_CHANGES] != nil) {
    includeMetadataChanges = [listenerOptions[KEY_INCLUDE_METADATA_CHANGES] boolValue];
  }


  id <FIRListenerRegistration> listener = [[firestoreQuery instance] addSnapshotListenerWithIncludeMetadataChanges:includeMetadataChanges listener:listenerBlock];
  collectionSnapshotListeners[listenerId] = listener;
}

RCT_EXPORT_METHOD(collectionOffSnapshot:
  (FIRApp *) firebaseApp
    :(NSString *)listenerId
) {
  id <FIRListenerRegistration> listener = collectionSnapshotListeners[listenerId];
  if (listener) {
    [listener remove];
    [collectionSnapshotListeners removeObjectForKey:listenerId];
  }
}

RCT_EXPORT_METHOD(collectionGet:
  (FIRApp *) firebaseApp
    :(NSString *)path
    :(NSString *)type
    :(NSArray *)filters
    :(NSArray *)orders
    :(NSDictionary *)options
    :(NSDictionary *)getOptions
    :(RCTPromiseResolveBlock)resolve
    :(RCTPromiseRejectBlock)reject
) {
  FIRFirestore *firestore = [RNFBFirestoreCommon getFirestoreForApp:firebaseApp];
  FIRQuery *query = [RNFBFirestoreCommon getQueryForFirestore:firestore path:path type:type];

  RNFBFirestoreQuery *firestoreQuery = [[RNFBFirestoreQuery alloc] initWithModifiers:firestore query:query filters:filters orders:orders options:options];

  FIRFirestoreSource source;

  if (getOptions[@"source"]) {
    if ([getOptions[@"source"] isEqualToString:@"server"]) {
      source = FIRFirestoreSourceServer;
    } else if ([getOptions[@"source"] isEqualToString:@"cache"]) {
      source = FIRFirestoreSourceCache;
    } else {
      source = FIRFirestoreSourceDefault;
    }
  } else {
    source = FIRFirestoreSourceDefault;
  }

  [[firestoreQuery instance] getDocumentsWithSource:source completion:^(FIRQuerySnapshot *snapshot, NSError *error) {
    if (error) {
      return [RNFBFirestoreCommon promiseRejectFirestoreException:reject error:error];
    } else {
      NSDictionary *serialized = [RNFBFirestoreSerialize querySnapshotToDictionary:snapshot];
      resolve(serialized);
    }
  }];
}

- (void)sendSnapshotEvent:(FIRApp *)firApp
                 snapshot:(FIRQuerySnapshot *)snapshot {
  NSDictionary *serialized = [RNFBFirestoreSerialize querySnapshotToDictionary:snapshot];
  [[RNFBRCTEventEmitter shared] sendEventWithName:RNFB_FIRESTORE_COLLECTION_SYNC body:@{
      @"appName": [RNFBSharedUtils getAppJavaScriptName:firApp.name],
      @"body": @{
          @"snapshot": serialized,
      }
  }];
}

- (void)sendSnapshotError:(FIRApp *)firApp
                    error:(NSError *)error {
  NSArray *codeAndMessage = [RNFBFirestoreCommon getCodeAndMessage:error];
  [[RNFBRCTEventEmitter shared] sendEventWithName:RNFB_FIRESTORE_COLLECTION_SYNC body:@{
      @"appName": [RNFBSharedUtils getAppJavaScriptName:firApp.name],
      @"body": @{
          @"error": @{
              @"code": codeAndMessage[0],
              @"message": codeAndMessage[1],
          }
      }
  }];
}

@end