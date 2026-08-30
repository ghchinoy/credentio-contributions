// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Native status codes returned by the Google Credentio C-ABI bridge.
 */
export enum CredentioStatusCode {
  /** Validation succeeded and produced a valid report. */
  OK = 0,
  /** Asset parsed successfully but contains no C2PA content credentials. */
  NO_CREDENTIALS = 1,
  /** Input parameter was invalid, null, or out of range. */
  INVALID_ARGUMENT = 2,
  /** Failed to read, decode, or write asset data. */
  IO_ERROR = 3,
  /** Internal error within the C2PA validation pipeline. */
  INTERNAL_ERROR = 4
}

/**
 * Exception class thrown when a Credentio WebAssembly operation fails.
 */
export class CredentioError extends Error {
  /** Optional native status code associated with the failure. */
  public readonly statusCode?: CredentioStatusCode;

  constructor(message: string, statusCode?: CredentioStatusCode) {
    super(message);
    this.name = 'CredentioError';
    this.statusCode = statusCode;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}
