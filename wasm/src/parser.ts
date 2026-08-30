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

import {
  type Assertion,
  classifyAssertion,
  createProvenanceReport,
  getManifestValidity,
  type Manifest,
  type ProvenanceReport,
  type Severity,
  type SignatureInfo,
  type ValidationStatus
} from './models.js';

/**
 * Deduplicates version strings containing repeated colon tokens (e.g. "969395858:969395858").
 */
function cleanGeneratorVersion(ver?: string | null): string | undefined {
  if (!ver || typeof ver !== 'string') {
    return undefined;
  }
  const parts = ver.split(':');
  if (parts.length === 2 && parts[0] && parts[0] === parts[1]) {
    return parts[0];
  }
  return ver;
}

/**
 * Classifies a validation status code string into coarse Severity (info, warning, error).
 */
function classifySeverity(code: string): Severity {
  const lowered = code.toLowerCase();
  if (lowered.includes('untrusted')) {
    // Untrusted certificates in test assets are surfaced as warnings
    return 'warning';
  }
  if (
    lowered.includes('not') ||
    lowered.includes('invalid') ||
    lowered.includes('mismatch') ||
    lowered.includes('missing') ||
    lowered.includes('fail') ||
    lowered.includes('error')
  ) {
    return 'error';
  }
  if (
    lowered.includes('validated') ||
    lowered.includes('trusted') ||
    lowered.includes('success') ||
    lowered.includes('ok')
  ) {
    return 'info';
  }
  return 'warning';
}

/**
 * Generates a human-readable summarized string for a C2PA assertion payload.
 */
function summarizeAssertion(label: string, value: any): string | undefined {
  if (!value || typeof value !== 'object') {
    return undefined;
  }

  // 1. Actions assertion (c2pa.actions, c2pa.actions.v2)
  const actions = value.actions;
  if (Array.isArray(actions)) {
    const names: string[] = [];
    for (const a of actions) {
      if (a && typeof a === 'object' && a.action) {
        const actionName = String(a.action);
        const dst = a.digitalSourceType || a.digital_source_type;
        if (dst && typeof dst === 'string' && dst.length > 0) {
          const cleanDst = dst.split('/').pop() || dst;
          names.push(`${actionName} (${cleanDst})`);
        } else {
          names.push(actionName);
        }
      }
    }
    if (names.length > 0) {
      return names.join(', ');
    }
  }

  // 2. Data hash assertion (c2pa.hash.data, c2pa.hash.bmff.v3)
  if ('hash_value' in value && value.hash_value != null) {
    const hv = String(value.hash_value);
    return `hash: ${hv.slice(0, 16)}…`;
  }

  // 3. Author assertion
  if (label.includes('author')) {
    if (Array.isArray(value.author) && value.author[0]?.name) {
      return `author: ${value.author[0].name}`;
    }
    if (value.author && typeof value.author === 'object' && value.author.name) {
      return `author: ${value.author.name}`;
    }
    if (value.name && typeof value.name === 'string') {
      return `author: ${value.name}`;
    }
  }

  // 4. AI Training and Mining assertion (c2pa.training-mining, c2pa.data-mining)
  if (label.includes('training-mining') || label.includes('data-mining')) {
    if (value.entries && typeof value.entries === 'object') {
      const formatted: string[] = [];
      const keys = Object.keys(value.entries).sort();
      for (const k of keys) {
        const entryVal = value.entries[k];
        const shortKey = k.replace(/^c2pa\./, '').replace(/^cawg\./, '');
        if (entryVal && typeof entryVal === 'object' && 'use' in entryVal) {
          formatted.push(`${shortKey}=${entryVal.use}`);
        } else if (typeof entryVal === 'string') {
          formatted.push(`${shortKey}=${entryVal}`);
        }
      }
      if (formatted.length > 0) {
        return `AI Training: ${formatted.join(', ')}`;
      }
    } else if (value.use && typeof value.use === 'string') {
      return `AI Training: ${value.use}`;
    }
  }

  // 5. Digital Source Type assertion (c2pa.digital_source_type, c2pa.digitalSourceType)
  if (label.includes('digital_source_type') || label.includes('digitalSourceType')) {
    const typeVal = value.digital_source_type || value.digitalSourceType || value.type;
    if (typeVal && typeof typeVal === 'string') {
      return typeVal.split('/').pop() || typeVal;
    }
  }

  // 6. AI Generative Info assertion (c2pa.generative, c2pa.inference, c2pa.ai_generative_info)
  if (label.includes('generative') || label.includes('inference')) {
    if (value.model && typeof value.model === 'object') {
      const modelName = value.model.name;
      const modelVer = value.model.version;
      const parts = [modelName, modelVer].filter(Boolean);
      if (parts.length > 0) {
        return `model: ${parts.join(' ')}`;
      }
    }
    if (value.model_name && typeof value.model_name === 'string') {
      return `model: ${value.model_name}`;
    }
    if (value.prompt && typeof value.prompt === 'string') {
      return `prompt: ${value.prompt}`;
    }
  }

  return undefined;
}

/**
 * Extracts signature details from a raw signature dictionary.
 */
function mapSignature(sigDict?: any): SignatureInfo | undefined {
  if (!sigDict || typeof sigDict !== 'object') {
    return undefined;
  }

  let issuer = sigDict.issuer || sigDict.common_name;
  const certInfo = sigDict.certificateInfo;
  if (!issuer && certInfo && typeof certInfo === 'object') {
    if (certInfo.issuer && typeof certInfo.issuer === 'object') {
      issuer = certInfo.issuer.CN;
    }
  }

  let certChainSummary = sigDict.cert_serial_number;
  if (!certChainSummary && certInfo && typeof certInfo === 'object') {
    certChainSummary = certInfo.serialNumber;
  }

  const algorithm = sigDict.alg || sigDict.algorithm;

  let time: Date | undefined;
  let timeStr = sigDict.time || sigDict.date_time;
  if (!timeStr && sigDict.timeStampInfo && typeof sigDict.timeStampInfo === 'object') {
    timeStr = sigDict.timeStampInfo.timestamp;
  }
  if (timeStr && typeof timeStr === 'string') {
    const parsed = new Date(timeStr);
    if (!isNaN(parsed.getTime())) {
      time = parsed;
    }
  }

  if (issuer || algorithm || time || certChainSummary) {
    return { issuer, algorithm, time, certChainSummary };
  }
  return undefined;
}

/**
 * Maps raw validation status records to typed ValidationStatus array.
 */
function mapValidationStatuses(array: any[], category?: string): ValidationStatus[] {
  if (!Array.isArray(array)) {
    return [];
  }
  const results: ValidationStatus[] = [];
  for (const item of array) {
    if (item && typeof item === 'object' && item.code) {
      const code = String(item.code);
      let sev = classifySeverity(code);
      if (category === 'failure') {
        sev = 'error';
      } else if (category === 'informational' || category === 'success') {
        sev = 'info';
      }
      results.push({
        code,
        explanation: item.explanation ? String(item.explanation) : undefined,
        url: item.url ? String(item.url) : undefined,
        severity: sev
      });
    }
  }
  return results;
}

/**
 * Maps a raw manifest dictionary into a typed Manifest object.
 */
function mapManifest(dict: any, defaultLabel: string): Manifest {
  const label = (dict && dict.label) ? String(dict.label) : defaultLabel;
  const title = dict?.title ? String(dict.title) : undefined;
  const format = dict?.format ? String(dict.format) : undefined;
  const isUpdateManifest = Boolean(dict?.is_update_manifest);

  const claimDict = dict?.claim || dict?.['claim.v2'] || {};

  // Claim generator extraction
  let claimGenerator: string | undefined;
  const genInfo = claimDict?.claim_generator_info || dict?.claim_generator_info;
  if (genInfo && typeof genInfo === 'object' && !Array.isArray(genInfo)) {
    const name = genInfo.name;
    const version = cleanGeneratorVersion(genInfo.version);
    const parts = [name, version].filter(Boolean);
    if (parts.length > 0) claimGenerator = parts.join(' ');
  } else if (Array.isArray(genInfo) && genInfo.length > 0 && typeof genInfo[0] === 'object' && genInfo[0] !== null) {
    const name = genInfo[0].name;
    const version = cleanGeneratorVersion(genInfo[0].version);
    const parts = [name, version].filter(Boolean);
    if (parts.length > 0) claimGenerator = parts.join(' ');
  }
  if (!claimGenerator) {
    claimGenerator = claimDict?.claim_generator || dict?.claim_generator;
  }

  // Signature extraction
  const sigDict =
    claimDict?.signature_info ||
    dict?.signature_info ||
    claimDict?.signature ||
    dict?.signature;
  const signature = mapSignature(sigDict);

  // Assertions extraction
  const assertions: Assertion[] = [];
  const rawAssertions = dict?.assertions;
  if (rawAssertions && typeof rawAssertions === 'object' && !Array.isArray(rawAssertions)) {
    for (const [aLabel, aVal] of Object.entries(rawAssertions)) {
      const kind = classifyAssertion(aLabel);
      const summary = summarizeAssertion(aLabel, aVal);
      assertions.push({ label: aLabel, kind, summary });
    }
  } else if (Array.isArray(rawAssertions)) {
    for (const entry of rawAssertions) {
      if (entry && typeof entry === 'object' && entry.label) {
        const aLabel = String(entry.label);
        const kind = classifyAssertion(aLabel);
        const summary = summarizeAssertion(aLabel, entry.data ?? entry);
        assertions.push({ label: aLabel, kind, summary });
      }
    }
  }
  assertions.sort((a, b) => a.label.localeCompare(b.label));

  // Validation statuses extraction
  let statuses: ValidationStatus[] = [];
  if (dict?.validation && typeof dict.validation === 'object' && Array.isArray(dict.validation.status)) {
    statuses = mapValidationStatuses(dict.validation.status);
  } else if (Array.isArray(dict?.validation_status)) {
    statuses = mapValidationStatuses(dict.validation_status);
  } else if (dict?.validationResults && typeof dict.validationResults === 'object') {
    for (const cat of ['failure', 'informational', 'success']) {
      if (Array.isArray(dict.validationResults[cat])) {
        statuses.push(...mapValidationStatuses(dict.validationResults[cat], cat));
      }
    }
  }

  const overallValidity = getManifestValidity(statuses);

  return {
    label,
    title,
    format,
    claimGenerator,
    isUpdateManifest,
    signature,
    assertions,
    validationStatuses: statuses,
    overallValidity
  };
}

/**
 * Parses raw crJSON output from the Google Credentio C-ABI bridge into a strongly typed ProvenanceReport.
 *
 * Supports both Google Credentio and c2patool manifest store structures, handling:
 * - Array and dictionary-based manifest collections
 * - C2PA v1 and v2 claim schemas (`claim` vs `claim.v2`)
 * - Active manifest resolution via `active_manifest` root key
 * - Generator version deduplication (e.g. `969395858:969395858`)
 * - Assertion classification and summarization
 * - Fallback validation statuses and overall badge rollups
 *
 * @param jsonStr Raw JSON string returned by the native validation engine.
 * @param mediaType Optional detected or user-supplied IANA media type.
 * @param elapsedSeconds Total wall-clock elapsed time in seconds.
 * @param coreSeconds Native engine internal processing time in seconds.
 * @param engineId Identifier of the validation engine.
 * @param engineName Human-readable name of the validation engine.
 * @returns Fully populated, typed ProvenanceReport.
 */
export function parseCrJSON(
  jsonStr: string,
  mediaType?: string,
  elapsedSeconds: number = 0.0,
  coreSeconds?: number,
  engineId: string = 'credentio-wasm',
  engineName: string = 'Credentio (WebAssembly)'
): ProvenanceReport {
  let root: any;
  try {
    root = JSON.parse(jsonStr);
  } catch {
    return createProvenanceReport({
      engineId,
      engineName,
      hasCredentials: false,
      elapsedSeconds,
      coreSeconds,
      mediaType,
      rawJson: jsonStr
    });
  }

  if (!root || typeof root !== 'object') {
    return createProvenanceReport({
      engineId,
      engineName,
      hasCredentials: false,
      elapsedSeconds,
      coreSeconds,
      mediaType,
      rawJson: jsonStr
    });
  }

  const manifests: Manifest[] = [];
  const rawManifests = root.manifests;

  if (Array.isArray(rawManifests)) {
    for (let idx = 0; idx < rawManifests.length; idx++) {
      const mDict = rawManifests[idx];
      if (mDict && typeof mDict === 'object') {
        manifests.push(mapManifest(mDict, `manifest_${idx}`));
      }
    }
  } else if (rawManifests && typeof rawManifests === 'object') {
    for (const [label, mDict] of Object.entries(rawManifests)) {
      if (mDict && typeof mDict === 'object') {
        manifests.push(mapManifest(mDict, label));
      }
    }
  }

  // Resolve active manifest
  const activeLabel = typeof root.active_manifest === 'string' ? root.active_manifest : undefined;
  let active: Manifest | undefined;
  let ingredients: Manifest[] = [];

  if (activeLabel) {
    const matched = manifests.find((m) => m.label === activeLabel);
    if (matched) {
      active = matched;
      ingredients = manifests.filter((m) => m.label !== activeLabel);
    } else {
      active = manifests[0];
      ingredients = manifests.slice(1);
    }
  } else {
    active = manifests[0];
    ingredients = manifests.slice(1);
  }

  // Fallback to root-level validation statuses if active manifest has none nested
  if (active && active.validationStatuses.length === 0) {
    let rootStatuses: ValidationStatus[] = [];
    if (Array.isArray(root.validation_status)) {
      rootStatuses = mapValidationStatuses(root.validation_status);
    } else if (Array.isArray(root.validation_results?.validation_status)) {
      rootStatuses = mapValidationStatuses(root.validation_results.validation_status);
    } else if (root.validationResults && typeof root.validationResults === 'object') {
      for (const cat of ['failure', 'informational', 'success']) {
        if (Array.isArray(root.validationResults[cat])) {
          rootStatuses.push(...mapValidationStatuses(root.validationResults[cat], cat));
        }
      }
    }

    if (rootStatuses.length > 0) {
      active.validationStatuses = rootStatuses;
      active.overallValidity = getManifestValidity(rootStatuses);
    }
  }

  // Propagate media type if manifest format is missing
  if (mediaType && mediaType.length > 0) {
    if (active && (!active.format || active.format.length === 0)) {
      active.format = mediaType;
    }
    for (const ing of ingredients) {
      if (!ing.format || ing.format.length === 0) {
        ing.format = mediaType;
      }
    }
  }

  const valResults = root.validation_results || {};
  const specVersion =
    root.spec_version ||
    valResults.spec_version ||
    valResults.version ||
    undefined;

  return createProvenanceReport({
    engineId,
    engineName,
    hasCredentials: active !== undefined,
    elapsedSeconds,
    coreSeconds,
    mediaType,
    specVersion: specVersion ? String(specVersion) : undefined,
    activeManifest: active,
    ingredientManifests: ingredients,
    rawJson: jsonStr
  });
}
