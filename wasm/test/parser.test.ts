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

import { describe, expect, it } from 'vitest';
import { parseCrJSON } from '../src/parser.js';
import {
  SAMPLE_AI_TRAINING_ASSERTIONS,
  SAMPLE_C2PATOOL_DICT_MANIFESTS,
  SAMPLE_CRJSON_V1,
  SAMPLE_CRJSON_V2,
  SAMPLE_INVALID_MANIFEST,
  SAMPLE_PORTLANDIA_MP4
} from './fixtures/crjson-samples.js';

describe('parseCrJSON Parser Resilience', () => {
  it('correctly parses C2PA v1 model structure', () => {
    const report = parseCrJSON(SAMPLE_CRJSON_V1, 'image/jpeg', 0.015, 0.012);

    expect(report.engineId).toBe('credentio-wasm');
    expect(report.engineName).toBe('Credentio (WebAssembly)');
    expect(report.hasCredentials).toBe(true);
    expect(report.badge).toBe('signed');
    expect(report.isVerified).toBe(true);
    expect(report.isInvalid).toBe(false);
    expect(report.specVersion).toBe('1.4');
    expect(report.mediaType).toBe('image/jpeg');
    expect(report.elapsedSeconds).toBeCloseTo(0.015);
    expect(report.coreSeconds).toBeCloseTo(0.012);

    const active = report.activeManifest;
    expect(active).toBeDefined();
    expect(active?.label).toBe('urn:uuid:active-v1-manifest');
    expect(active?.title).toBe('Landscape Photograph');
    expect(active?.format).toBe('image/jpeg');
    expect(active?.claimGenerator).toBe('Credentio C2PA Tool 1.4.2');
    expect(report.primaryClaimGenerator).toBe('Credentio C2PA Tool 1.4.2');

    // Signature
    expect(active?.signature).toBeDefined();
    expect(active?.signature?.issuer).toBe('Google Authenticity CA');
    expect(report.primarySignerIssuer).toBe('Google Authenticity CA');
    expect(active?.signature?.algorithm).toBe('es256');
    expect(active?.signature?.certChainSummary).toBe('9876543210');
    expect(active?.signature?.time).toBeInstanceOf(Date);
    expect(active?.signature?.time?.toISOString()).toBe('2026-08-30T12:00:00.000Z');

    // Assertions
    expect(active?.assertions.length).toBe(2);
    const actionsAssertion = active?.assertions.find((a) => a.kind === 'actions');
    expect(actionsAssertion).toBeDefined();
    expect(actionsAssertion?.summary).toBe('c2pa.created, c2pa.color_adjustments');

    const hashAssertion = active?.assertions.find((a) => a.kind === 'hash');
    expect(hashAssertion).toBeDefined();
    expect(hashAssertion?.summary).toBe('hash: 9f86d081884c7d65…');

    // Validation status
    expect(active?.validationStatuses.length).toBe(1);
    expect(active?.validationStatuses[0].code).toBe('claimSignature.validated');
    expect(active?.validationStatuses[0].severity).toBe('info');
    expect(active?.overallValidity).toBe('signed');
  });

  it('correctly parses C2PA v2 schema and toolkit formats', () => {
    const report = parseCrJSON(SAMPLE_CRJSON_V2, 'image/png');

    expect(report.hasCredentials).toBe(true);
    expect(report.specVersion).toBe('2.2');
    expect(report.badge).toBe('signed');
    expect(report.isVerified).toBe(true);

    const active = report.activeManifest;
    expect(active?.label).toBe('urn:uuid:v2-manifest-001');
    expect(active?.title).toBe('Digital Artwork v2');
    expect(active?.claimGenerator).toBe('Photoshop 26.1.0');

    // Nested certificate info extraction
    expect(active?.signature?.issuer).toBe('Adobe Content Authenticity CA');
    expect(active?.signature?.certChainSummary).toBe('A1B2C3D4E5F6');
    expect(active?.signature?.algorithm).toBe('rs256');
    expect(active?.signature?.time?.toISOString()).toBe('2026-08-30T14:45:00.000Z');

    // Actions with digitalSourceType
    const actionsAssertion = active?.assertions.find((a) => a.kind === 'actions');
    expect(actionsAssertion?.summary).toBe('c2pa.created (digitalCapture)');

    // Categorized validation results
    expect(active?.validationStatuses.length).toBe(2);
    expect(active?.validationStatuses.every((s) => s.severity === 'info')).toBe(true);
  });

  it('deduplicates generator version strings (e.g. 969395858:969395858)', () => {
    const report = parseCrJSON(SAMPLE_PORTLANDIA_MP4, 'video/mp4');

    expect(report.hasCredentials).toBe(true);
    const active = report.activeManifest;
    expect(active?.claimGenerator).toBe('Credentio Probe Engine 969395858');
    expect(active?.format).toBe('video/mp4');

    const actionsAssertion = active?.assertions.find((a) => a.kind === 'actions');
    expect(actionsAssertion?.summary).toBe('c2pa.created (trainedAlgorithmicMedia), c2pa.edited');
  });

  it('parses AI training, mining, and generative info assertions', () => {
    const report = parseCrJSON(SAMPLE_AI_TRAINING_ASSERTIONS, 'image/webp');

    expect(report.hasCredentials).toBe(true);
    const active = report.activeManifest;

    const aiAssertion = active?.assertions.find((a) => a.kind === 'ai_training_mining');
    expect(aiAssertion).toBeDefined();
    expect(aiAssertion?.summary).toBe(
      'AI Training: ai_generative_training=notAllowed, ai_inference=allowed, data_mining=notAllowed'
    );

    const dstAssertion = active?.assertions.find((a) => a.label === 'c2pa.digital_source_type');
    expect(dstAssertion?.summary).toBe('trainedAlgorithmicMedia');

    const genAssertion = active?.assertions.find((a) => a.label === 'c2pa.generative');
    expect(genAssertion?.summary).toBe('model: Imagen 3.0');

    const authorAssertion = active?.assertions.find((a) => a.label === 'c2pa.author');
    expect(authorAssertion?.summary).toBe('author: Credentio Author');
  });

  it('parses c2patool dictionary keyed manifests with active_manifest resolution', () => {
    const report = parseCrJSON(SAMPLE_C2PATOOL_DICT_MANIFESTS, 'image/jpeg');

    expect(report.hasCredentials).toBe(true);
    expect(report.activeManifest?.label).toBe('urn:uuid:active-c2patool-manifest');
    expect(report.ingredientManifests.length).toBe(1);
    expect(report.ingredientManifests[0].label).toBe('urn:uuid:ingredient-manifest-01');

    // Inherited root-level validation status
    expect(report.activeManifest?.validationStatuses.length).toBe(1);
    expect(report.activeManifest?.validationStatuses[0].code).toBe('signingCredential.untrusted');
    expect(report.activeManifest?.validationStatuses[0].severity).toBe('warning');
    // Untrusted certificate is a warning, so badge is signed
    expect(report.badge).toBe('signed');
    expect(report.isVerified).toBe(true);
  });

  it('properly rolls up validation failures into invalid badge state', () => {
    const report = parseCrJSON(SAMPLE_INVALID_MANIFEST, 'image/jpeg');

    expect(report.hasCredentials).toBe(true);
    expect(report.badge).toBe('invalid');
    expect(report.isVerified).toBe(false);
    expect(report.isInvalid).toBe(true);

    const active = report.activeManifest;
    expect(active?.overallValidity).toBe('invalid');
    expect(active?.validationStatuses[0].severity).toBe('error');
    expect(active?.validationStatuses[0].code).toBe('hash.mismatch');
  });

  it('gracefully handles corrupt or malformed JSON payloads', () => {
    const reportCorrupt = parseCrJSON('NOT_A_VALID_JSON_STRING{{{', 'image/jpeg', 0.005);
    expect(reportCorrupt.hasCredentials).toBe(false);
    expect(reportCorrupt.badge).toBe('unsigned');
    expect(reportCorrupt.isVerified).toBe(false);
    expect(reportCorrupt.isInvalid).toBe(false);
    expect(reportCorrupt.activeManifest).toBeUndefined();
    expect(reportCorrupt.rawJson).toBe('NOT_A_VALID_JSON_STRING{{{');

    const reportEmpty = parseCrJSON('', 'image/jpeg');
    expect(reportEmpty.hasCredentials).toBe(false);
    expect(reportEmpty.badge).toBe('unsigned');

    const reportNumber = parseCrJSON('12345', 'image/jpeg');
    expect(reportNumber.hasCredentials).toBe(false);
  });

  it('inherits supplied mediaType when manifest format is missing', () => {
    const jsonWithoutFormat = JSON.stringify({
      manifests: [
        {
          label: 'urn:uuid:no-format-manifest',
          claim: { claim_generator: 'App 1.0' }
        }
      ]
    });

    const report = parseCrJSON(jsonWithoutFormat, 'image/webp');
    expect(report.activeManifest?.format).toBe('image/webp');
  });

  it('safely handles malformed claim_generator_info arrays with null, undefined, and primitives without TypeError', () => {
    // 1. claim_generator_info with [null]
    const jsonNullGenInfo = JSON.stringify({
      manifests: [
        {
          label: 'urn:uuid:null-gen-info-manifest',
          claim: {
            claim_generator_info: [null],
            claim_generator: 'Fallback Generator 1.0'
          }
        }
      ]
    });
    const reportNull = parseCrJSON(jsonNullGenInfo, 'image/jpeg');
    expect(reportNull.hasCredentials).toBe(true);
    expect(reportNull.activeManifest?.claimGenerator).toBe('Fallback Generator 1.0');

    // 2. claim_generator_info with [undefined]
    const jsonUndefinedGenInfo = JSON.stringify({
      manifests: [
        {
          label: 'urn:uuid:undefined-gen-info-manifest',
          claim: {
            claim_generator_info: [undefined],
            claim_generator: 'Fallback Generator 2.0'
          }
        }
      ]
    });
    const reportUndefined = parseCrJSON(jsonUndefinedGenInfo, 'image/jpeg');
    expect(reportUndefined.hasCredentials).toBe(true);
    expect(reportUndefined.activeManifest?.claimGenerator).toBe('Fallback Generator 2.0');

    // 3. claim_generator_info with primitive elements [123, 'str']
    const jsonPrimitiveGenInfo = JSON.stringify({
      manifests: [
        {
          label: 'urn:uuid:primitive-gen-info-manifest',
          claim: {
            claim_generator_info: [123, 'string-val']
          }
        }
      ]
    });
    const reportPrimitive = parseCrJSON(jsonPrimitiveGenInfo, 'image/jpeg');
    expect(reportPrimitive.hasCredentials).toBe(true);
    expect(reportPrimitive.activeManifest?.claimGenerator).toBeUndefined();

    // 4. claim_generator_info with null object or empty array
    const jsonEmptyGenInfo = JSON.stringify({
      manifests: [
        {
          label: 'urn:uuid:empty-gen-info-manifest',
          claim: {
            claim_generator_info: []
          }
        }
      ]
    });
    const reportEmpty = parseCrJSON(jsonEmptyGenInfo, 'image/jpeg');
    expect(reportEmpty.hasCredentials).toBe(true);
    expect(reportEmpty.activeManifest?.claimGenerator).toBeUndefined();

    // 5. claim_generator_info with null properties
    const jsonNullProps = JSON.stringify({
      manifests: [
        {
          label: 'urn:uuid:null-props-manifest',
          claim: {
            claim_generator_info: [{ name: null, version: null }]
          }
        }
      ]
    });
    const reportNullProps = parseCrJSON(jsonNullProps, 'image/jpeg');
    expect(reportNullProps.hasCredentials).toBe(true);
    expect(reportNullProps.activeManifest?.claimGenerator).toBeUndefined();
  });

  it('safely handles heavily malformed nested structures with null and invalid types', () => {
    const malformedStructure = JSON.stringify({
      manifests: [
        null,
        undefined,
        123,
        'not an object',
        {
          label: 'urn:uuid:deeply-malformed',
          claim: null,
          signature_info: {
            issuer: null,
            certificateInfo: null,
            timeStampInfo: null
          },
          assertions: [
            null,
            undefined,
            {},
            {
              label: 'c2pa.actions',
              actions: [null, undefined, {}, { action: 'c2pa.created' }]
            },
            {
              label: 'c2pa.author',
              author: [null, { name: 'Valid Author' }]
            },
            {
              label: 'c2pa.training-mining',
              entries: {
                'c2pa.ai_generative_training': null,
                'c2pa.data_mining': { use: 'notAllowed' }
              }
            },
            {
              label: 'c2pa.generative',
              model: null
            }
          ],
          validationResults: {
            failure: [null, { code: 'hash.mismatch', explanation: null }],
            informational: [null, undefined],
            success: null
          }
        }
      ],
      validation_results: null,
      active_manifest: 'urn:uuid:deeply-malformed'
    });

    const report = parseCrJSON(malformedStructure, 'image/jpeg');
    expect(report.hasCredentials).toBe(true);
    expect(report.activeManifest?.label).toBe('urn:uuid:deeply-malformed');
    expect(report.activeManifest?.assertions.length).toBe(4);
    expect(report.activeManifest?.validationStatuses.length).toBe(1);
    expect(report.activeManifest?.validationStatuses[0].code).toBe('hash.mismatch');
  });
});
