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

/** At-a-glance credential validation state for UI badging. */
export type BadgeState = 'signed' | 'unsigned' | 'invalid';

/** Coarse severity level for C2PA validation status entries. */
export type Severity = 'info' | 'warning' | 'error';

/** Broad category classification for C2PA assertions. */
export type AssertionKind =
  | 'actions'
  | 'ingredient'
  | 'thumbnail'
  | 'ai_training_mining'
  | 'metadata'
  | 'hash'
  | 'other';

/**
 * Classifies an assertion label URI into a coarse AssertionKind.
 */
export function classifyAssertion(label: string): AssertionKind {
  const lowered = label.toLowerCase();
  if (lowered.includes('action')) return 'actions';
  if (lowered.includes('ingredient')) return 'ingredient';
  if (lowered.includes('thumbnail')) return 'thumbnail';
  if (lowered.includes('training-mining') || lowered.includes('data-mining') || lowered.includes('ai')) {
    return 'ai_training_mining';
  }
  if (lowered.includes('hash')) return 'hash';
  if (lowered.includes('metadata') || lowered.includes('exif') || lowered.includes('xmp')) {
    return 'metadata';
  }
  return 'other';
}

/** Signature and cryptographic issuer metadata for a C2PA manifest. */
export interface SignatureInfo {
  /** Common name or certificate authority of the signing certificate. */
  issuer?: string;
  /** Cryptographic signing algorithm (e.g. 'es256', 'rs256'). */
  algorithm?: string;
  /** Time the claim was signed or timestamped by a TSA. */
  time?: Date;
  /** Certificate serial number or certificate chain summary. */
  certChainSummary?: string;
}

/** Individual assertion attached to a C2PA manifest claim. */
export interface Assertion {
  /** Full assertion label URI (e.g. 'c2pa.actions', 'c2pa.hash.data'). */
  label: string;
  /** Coarse category of the assertion. */
  kind: AssertionKind;
  /** Human-readable summarized representation of assertion payload. */
  summary?: string;
}

/** Detailed validation status code returned by the C2PA validation engine. */
export interface ValidationStatus {
  /** Standard C2PA status code string (e.g. 'claimSignature.validated'). */
  code: string;
  /** Human explanation if provided by the engine. */
  explanation?: string;
  /** JUMBF URI associated with the validation status. */
  url?: string;
  /** Coarse severity level. */
  severity: Severity;
}

/** Verifiable C2PA manifest containing claim metadata, assertions, and signatures. */
export interface Manifest {
  /** Unique manifest label within the manifest store. */
  label: string;
  /** Human title of the asset, if declared. */
  title?: string;
  /** Declared media format or detected IANA media type. */
  format?: string;
  /** Generator software name and version that produced the claim. */
  claimGenerator?: string;
  /** Whether this manifest is an update to an existing manifest store. */
  isUpdateManifest: boolean;
  /** Cryptographic signature information. */
  signature?: SignatureInfo;
  /** List of assertions contained in the manifest. */
  assertions: Assertion[];
  /** List of validation status records. */
  validationStatuses: ValidationStatus[];
  /** Rollup badge validity for this specific manifest. */
  overallValidity: BadgeState;
}

/**
 * Evaluates the overall validity of a manifest based on its validation statuses.
 */
export function getManifestValidity(statuses: ValidationStatus[]): BadgeState {
  if (statuses.some((s) => s.severity === 'error')) {
    return 'invalid';
  }
  return 'signed';
}

/** Top-level provenance report produced by Google Credentio verification. */
export interface ProvenanceReport {
  /** Identifier of the validation engine. */
  engineId: string;
  /** Human-readable name of the validation engine. */
  engineName: string;
  /** True if C2PA credentials were found in the asset. */
  hasCredentials: boolean;
  /** Total wall-clock time in seconds spent producing the report. */
  elapsedSeconds: number;
  /** Native engine internal processing time in seconds (excluding I/O). */
  coreSeconds?: number;
  /** IANA media type of the asset (e.g. 'image/jpeg', 'video/mp4'). */
  mediaType?: string;
  /** C2PA specification version reported by the engine (e.g. '2.2'). */
  specVersion?: string;
  /** Active (most recent) manifest in the asset's history. */
  activeManifest?: Manifest;
  /** Historical ingredient manifests contributing to the asset. */
  ingredientManifests: Manifest[];
  /** Raw JSON payload returned by the validation engine. */
  rawJson?: string;
  /** Overall badge status of the asset. */
  badge: BadgeState;
  /** Convenience getter: true if credentials exist and badge is signed. */
  isVerified: boolean;
  /** Convenience getter: true if credentials exist but badge is invalid. */
  isInvalid: boolean;
  /** Primary generator software from active manifest. */
  primaryClaimGenerator?: string;
  /** Primary signing authority issuer from active manifest. */
  primarySignerIssuer?: string;
}

/** Parameters for creating a ProvenanceReport. */
export interface CreateProvenanceReportParams {
  engineId: string;
  engineName: string;
  hasCredentials: boolean;
  elapsedSeconds: number;
  coreSeconds?: number;
  mediaType?: string;
  specVersion?: string;
  activeManifest?: Manifest;
  ingredientManifests?: Manifest[];
  rawJson?: string;
}

/**
 * Factory function to construct a ProvenanceReport with computed badge properties.
 */
export function createProvenanceReport(params: CreateProvenanceReportParams): ProvenanceReport {
  const {
    engineId,
    engineName,
    hasCredentials,
    elapsedSeconds,
    coreSeconds,
    mediaType,
    specVersion,
    activeManifest,
    ingredientManifests = [],
    rawJson
  } = params;

  let badge: BadgeState;
  if (!hasCredentials || !activeManifest) {
    badge = hasCredentials ? 'invalid' : 'unsigned';
  } else {
    badge = activeManifest.overallValidity;
  }

  const isVerified = badge === 'signed';
  const isInvalid = badge === 'invalid';
  const primaryClaimGenerator = activeManifest?.claimGenerator;
  const primarySignerIssuer = activeManifest?.signature?.issuer;

  return {
    engineId,
    engineName,
    hasCredentials,
    elapsedSeconds,
    coreSeconds,
    mediaType,
    specVersion,
    activeManifest,
    ingredientManifests,
    rawJson,
    badge,
    isVerified,
    isInvalid,
    primaryClaimGenerator,
    primarySignerIssuer
  };
}
