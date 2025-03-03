/*
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

import { NativeFirebaseError } from '@react-native-firebase/app/lib/internal';
import { isNull, isString, isObject } from '@react-native-firebase/common';

const SETTABLE_FIELDS = [
  'cacheControl',
  'contentDisposition',
  'contentEncoding',
  'contentLanguage',
  'contentType',
  'customMetadata',
];

export function handleStorageEvent(storageInstance, event) {
  const { taskId, eventName } = event;
  const body = event.body || {};

  if (body.error) {
    body.error = NativeFirebaseError.fromEvent(body.error, storageInstance._config.namespace);
  }

  storageInstance.emitter.emit(storageInstance.eventNameForApp(taskId, eventName), body);
}

// https://regex101.com/r/99E00o/2/
export function getHttpUrlParts(url) {
  const parts = url.match(
    /\/b\/(?<bucket>.*)\.appspot.com\/o\/(?<path>[a-zA-Z0-9./\-_]+)(?<params>.*)/,
  );

  if (!parts || parts.length < 3) {
    return null;
  }

  return { bucket: `gs://${parts[1]}`, path: parts[2] };
}

export function getGsUrlParts(url) {
  const bucket = url.substring(0, url.indexOf('/', 5)) || url;
  const path =
    (url.indexOf('/', 5) > -1 ? url.substring(url.indexOf('/', 5) + 1, url.length) : '/') || '/';

  return { bucket, path };
}

export function validateMetadata(metadata) {
  if (!isObject(metadata)) {
    throw new Error(`firebase.storage.SettableMetadata must be an object value if provided.`);
  }

  const metadataEntries = Object.entries(metadata);

  for (let i = 0; i < metadataEntries.length; i++) {
    const [key, value] = metadataEntries[i];
    // validate keys
    if (!SETTABLE_FIELDS.includes(key)) {
      throw new Error(
        `firebase.storage.SettableMetadata unknown property '${key}' provided for metadata.`,
      );
    }

    // validate values
    if (key !== 'customMetadata') {
      if (!isString(value) && !isNull(value)) {
        throw new Error(
          `firebase.storage.SettableMetadata invalid property '${key}' should be a string or null value.`,
        );
      }
    } else if (!isObject(value)) {
      throw new Error(
        `firebase.storage.SettableMetadata.customMetadata must be an object of keys and string values.`,
      );
    }
  }

  return metadata;
}
