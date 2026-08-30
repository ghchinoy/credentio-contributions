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

/** Standard C2PA v1 sample manifest JSON string. */
export const SAMPLE_CRJSON_V1 = JSON.stringify({
  spec_version: '1.4',
  manifests: [
    {
      label: 'urn:uuid:active-v1-manifest',
      title: 'Landscape Photograph',
      format: 'image/jpeg',
      claim: {
        claim_generator_info: {
          name: 'Credentio C2PA Tool',
          version: '1.4.2'
        },
        signature_info: {
          issuer: 'Google Authenticity CA',
          alg: 'es256',
          time: '2026-08-30T12:00:00Z',
          cert_serial_number: '9876543210'
        }
      },
      assertions: {
        'c2pa.actions': {
          actions: [
            { action: 'c2pa.created' },
            { action: 'c2pa.color_adjustments' }
          ]
        },
        'c2pa.hash.data': {
          hash_value: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08'
        }
      },
      validation: {
        status: [
          {
            code: 'claimSignature.validated',
            explanation: 'Signature is cryptographically valid'
          }
        ]
      }
    }
  ]
});

/** C2PA v2 schema sample with claim.v2 and categorized validationResults. */
export const SAMPLE_CRJSON_V2 = JSON.stringify({
  validation_results: {
    spec_version: '2.2'
  },
  manifests: [
    {
      label: 'urn:uuid:v2-manifest-001',
      title: 'Digital Artwork v2',
      format: 'image/png',
      'claim.v2': {
        claim_generator_info: [
          {
            name: 'Photoshop',
            version: '26.1.0'
          }
        ],
        signature_info: {
          certificateInfo: {
            issuer: {
              CN: 'Adobe Content Authenticity CA'
            },
            serialNumber: 'A1B2C3D4E5F6'
          },
          algorithm: 'rs256',
          timeStampInfo: {
            timestamp: '2026-08-30T14:45:00Z'
          }
        }
      },
      assertions: [
        {
          label: 'c2pa.actions.v2',
          data: {
            actions: [
              {
                action: 'c2pa.created',
                digitalSourceType: 'https://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture'
              }
            ]
          }
        },
        {
          label: 'c2pa.hash.bmff.v3',
          data: {
            hash_value: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'
          }
        }
      ],
      validationResults: {
        success: [
          {
            code: 'claimSignature.validated',
            explanation: 'Claim signature is valid'
          }
        ],
        informational: [
          {
            code: 'signingCredential.trusted',
            explanation: 'Root certificate is in trust store'
          }
        ]
      }
    }
  ]
});

/** Portlandia probe MP4 sample with version deduplication and digitalSourceType. */
export const SAMPLE_PORTLANDIA_MP4 = JSON.stringify({
  manifests: [
    {
      label: 'urn:uuid:portlandia-mp4-manifest',
      claim: {
        claim_generator_info: {
          name: 'Credentio Probe Engine',
          version: '969395858:969395858'
        },
        signature_info: {
          common_name: 'Media Authenticity Authority',
          alg: 'es256'
        }
      },
      assertions: {
        'c2pa.actions.v2': {
          actions: [
            {
              action: 'c2pa.created',
              digital_source_type: 'https://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia'
            },
            {
              action: 'c2pa.edited'
            }
          ]
        }
      },
      validation_status: [
        {
          code: 'claimSignature.validated'
        }
      ]
    }
  ]
});

/** AI training, mining, and generative info assertions sample. */
export const SAMPLE_AI_TRAINING_ASSERTIONS = JSON.stringify({
  manifests: [
    {
      label: 'urn:uuid:ai-training-manifest',
      title: 'Synthesized Landscape',
      format: 'image/webp',
      claim: {
        claim_generator: 'GenAI Studio 3.0',
        signature: {
          issuer: 'AI Content CA'
        }
      },
      assertions: {
        'c2pa.training-mining': {
          entries: {
            'c2pa.ai_generative_training': { use: 'notAllowed' },
            'cawg.data_mining': { use: 'notAllowed' },
            'c2pa.ai_inference': { use: 'allowed' }
          }
        },
        'c2pa.digital_source_type': {
          type: 'https://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia'
        },
        'c2pa.generative': {
          model: {
            name: 'Imagen',
            version: '3.0'
          },
          prompt: 'A serene mountain lake at sunrise'
        },
        'c2pa.author': {
          name: 'Credentio Author'
        }
      },
      validation: {
        status: [{ code: 'claimSignature.validated' }]
      }
    }
  ]
});

/** c2patool dictionary keyed manifest store with active_manifest root pointer. */
export const SAMPLE_C2PATOOL_DICT_MANIFESTS = JSON.stringify({
  active_manifest: 'urn:uuid:active-c2patool-manifest',
  validation_status: [
    {
      code: 'signingCredential.untrusted',
      explanation: 'Test certificate not anchored in standard trust store'
    }
  ],
  manifests: {
    'urn:uuid:active-c2patool-manifest': {
      label: 'urn:uuid:active-c2patool-manifest',
      title: 'Composite Asset',
      claim: {
        claim_generator: 'c2patool 0.9.0',
        signature_info: {
          issuer: 'Test Signing Cert'
        }
      },
      assertions: {
        'c2pa.actions': {
          actions: [{ action: 'c2pa.placed' }]
        }
      }
    },
    'urn:uuid:ingredient-manifest-01': {
      label: 'urn:uuid:ingredient-manifest-01',
      title: 'Background Image',
      format: 'image/jpeg',
      claim: {
        claim_generator: 'Camera Sensor 1.0'
      },
      assertions: {
        'c2pa.actions': {
          actions: [{ action: 'c2pa.created' }]
        }
      },
      validation: {
        status: [{ code: 'claimSignature.validated' }]
      }
    }
  }
});

/** Manifest containing validation error (invalid signature / hash mismatch). */
export const SAMPLE_INVALID_MANIFEST = JSON.stringify({
  manifests: [
    {
      label: 'urn:uuid:invalid-tampered-manifest',
      title: 'Tampered Asset',
      format: 'image/jpeg',
      claim: {
        claim_generator: 'Credentio 1.0',
        signature_info: { issuer: 'Google LLC' }
      },
      assertions: {
        'c2pa.actions': {
          actions: [{ action: 'c2pa.created' }]
        }
      },
      validationResults: {
        failure: [
          {
            code: 'hash.mismatch',
            explanation: 'Asset data hash does not match claim assertion'
          }
        ]
      }
    }
  ]
});
