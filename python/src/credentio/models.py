# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
import json
from typing import Any, Dict, List, Optional

class BadgeState(str, Enum):
    SIGNED = "signed"
    UNSIGNED = "unsigned"
    INVALID = "invalid"

class Severity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"

class AssertionKind(str, Enum):
    ACTIONS = "actions"
    INGREDIENT = "ingredient"
    THUMBNAIL = "thumbnail"
    AI_TRAINING_MINING = "ai_training_mining"
    METADATA = "metadata"
    HASH = "hash"
    OTHER = "other"

    @classmethod
    def classify(cls, label: str) -> "AssertionKind":
        lowered = label.lower()
        if "action" in lowered:
            return cls.ACTIONS
        if "ingredient" in lowered:
            return cls.INGREDIENT
        if "thumbnail" in lowered:
            return cls.THUMBNAIL
        if "training-mining" in lowered or "ai" in lowered:
            return cls.AI_TRAINING_MINING
        if "hash" in lowered:
            return cls.HASH
        if "metadata" in lowered or "exif" in lowered or "xmp" in lowered:
            return cls.METADATA
        return cls.OTHER

@dataclass
class SignatureInfo:
    issuer: Optional[str] = None
    algorithm: Optional[str] = None
    time: Optional[datetime] = None
    cert_chain_summary: Optional[str] = None

@dataclass
class Assertion:
    label: str
    kind: AssertionKind
    summary: Optional[str] = None

@dataclass
class ValidationStatus:
    code: str
    explanation: Optional[str] = None
    url: Optional[str] = None
    severity: Severity = Severity.INFO

@dataclass
class Manifest:
    label: str
    title: Optional[str] = None
    format: Optional[str] = None
    claim_generator: Optional[str] = None
    is_update_manifest: bool = False
    signature: Optional[SignatureInfo] = None
    assertions: List[Assertion] = field(default_factory=list)
    validation_statuses: List[ValidationStatus] = field(default_factory=list)

    @property
    def overall_validity(self) -> BadgeState:
        if any(s.severity == Severity.ERROR for s in self.validation_statuses):
            return BadgeState.INVALID
        return BadgeState.SIGNED

@dataclass
class ProvenanceReport:
    engine_id: str
    engine_name: str
    has_credentials: bool
    elapsed_seconds: float
    core_seconds: Optional[float] = None
    media_type: Optional[str] = None
    spec_version: Optional[str] = None
    active_manifest: Optional[Manifest] = None
    ingredient_manifests: List[Manifest] = field(default_factory=list)
    raw_json: Optional[str] = None

    @property
    def badge(self) -> BadgeState:
        if not self.has_credentials or not self.active_manifest:
            return BadgeState.INVALID if self.has_credentials else BadgeState.UNSIGNED
        return self.active_manifest.overall_validity


def _classify_severity(code: str) -> Severity:
    lowered = code.lower()
    if any(k in lowered for k in ("not", "invalid", "mismatch", "missing", "untrusted", "fail", "error")):
        return Severity.ERROR
    if any(k in lowered for k in ("validated", "trusted", "success", "ok")):
        return Severity.INFO
    return Severity.WARNING


def parse_crjson(
    raw_json: str,
    media_type: Optional[str] = None,
    elapsed_seconds: float = 0.0,
    core_seconds: Optional[float] = None,
    engine_id: str = "credentio",
    engine_name: str = "Credentio (Google)"
) -> ProvenanceReport:
    """Parses Credentio crJSON format into a typed ProvenanceReport."""
    try:
        root: Dict[str, Any] = json.loads(raw_json)
    except Exception:
        return ProvenanceReport(
            engine_id=engine_id,
            engine_name=engine_name,
            has_credentials=False,
            elapsed_seconds=elapsed_seconds,
            core_seconds=core_seconds,
            media_type=media_type,
            raw_json=raw_json
        )

    manifests: List[Manifest] = []

    raw_manifests = root.get("manifests", [])
    if isinstance(raw_manifests, list):
        for idx, m_dict in enumerate(raw_manifests):
            if isinstance(m_dict, dict):
                manifests.append(_map_manifest(m_dict, default_label=f"manifest_{idx}"))
    elif isinstance(raw_manifests, dict):
        for label, m_dict in raw_manifests.items():
            if isinstance(m_dict, dict):
                manifests.append(_map_manifest(m_dict, default_label=label))

    if media_type:
        for m in manifests:
            if not m.format:
                m.format = media_type

    active = manifests[0] if manifests else None
    ingredients = manifests[1:] if len(manifests) > 1 else []

    val_results = root.get("validation_results", {})
    spec_version = root.get("spec_version") or val_results.get("spec_version") or val_results.get("version")

    return ProvenanceReport(
        engine_id=engine_id,
        engine_name=engine_name,
        has_credentials=active is not None,
        elapsed_seconds=elapsed_seconds,
        core_seconds=core_seconds,
        media_type=media_type,
        spec_version=spec_version,
        active_manifest=active,
        ingredient_manifests=ingredients,
        raw_json=raw_json
    )


def _clean_generator_version(ver: Optional[str]) -> Optional[str]:
    if not ver or not isinstance(ver, str):
        return ver
    parts = ver.split(":")
    if len(parts) == 2 and parts[0] and parts[0] == parts[1]:
        return parts[0]
    return ver


def _map_manifest(dict_: Dict[str, Any], default_label: str) -> Manifest:
    label = dict_.get("label", default_label)
    title = dict_.get("title")
    format_ = dict_.get("format")
    is_update = dict_.get("is_update_manifest", False)

    claim_dict = dict_.get("claim") or dict_.get("claim.v2") or {}

    # Generator extraction
    claim_generator = None
    gen_info = claim_dict.get("claim_generator_info") or dict_.get("claim_generator_info")
    if isinstance(gen_info, dict):
        name = gen_info.get("name")
        ver = _clean_generator_version(gen_info.get("version"))
        claim_generator = " ".join(filter(None, [name, ver])) or None
    elif isinstance(gen_info, list) and len(gen_info) > 0:
        first = gen_info[0]
        if isinstance(first, dict):
            name = first.get("name")
            ver = _clean_generator_version(first.get("version"))
            claim_generator = " ".join(filter(None, [name, ver])) or None
    if not claim_generator:
        claim_generator = claim_dict.get("claim_generator") or dict_.get("claim_generator")

    # Signature
    sig_dict = claim_dict.get("signature_info") or dict_.get("signature_info") or claim_dict.get("signature") or dict_.get("signature")
    signature = None
    if isinstance(sig_dict, dict):
        issuer = sig_dict.get("issuer") or sig_dict.get("common_name")
        cert_info = sig_dict.get("certificateInfo")
        if not issuer and isinstance(cert_info, dict):
            iss_obj = cert_info.get("issuer")
            if isinstance(iss_obj, dict):
                issuer = iss_obj.get("CN")
        cert_summary = sig_dict.get("cert_serial_number")
        if not cert_summary and isinstance(cert_info, dict):
            cert_summary = cert_info.get("serialNumber")
        time_val = None
        time_str = sig_dict.get("time") or sig_dict.get("date_time")
        if not time_str and isinstance(sig_dict.get("timeStampInfo"), dict):
            time_str = sig_dict["timeStampInfo"].get("timestamp")
        if time_str:
            try:
                time_val = datetime.fromisoformat(time_str.replace("Z", "+00:00"))
            except Exception:
                time_val = None
        signature = SignatureInfo(
            issuer=issuer,
            algorithm=sig_dict.get("alg") or sig_dict.get("algorithm"),
            time=time_val,
            cert_chain_summary=cert_summary
        )

    # Assertions
    assertions: List[Assertion] = []
    raw_assertions = dict_.get("assertions", {})
    if isinstance(raw_assertions, dict):
        for a_label, a_val in raw_assertions.items():
            kind = AssertionKind.classify(a_label)
            summary = _summarize_assertion(a_label, a_val)
            assertions.append(Assertion(label=a_label, kind=kind, summary=summary))
    elif isinstance(raw_assertions, list):
        for entry in raw_assertions:
            if isinstance(entry, dict) and "label" in entry:
                a_label = entry["label"]
                kind = AssertionKind.classify(a_label)
                summary = _summarize_assertion(a_label, entry.get("data", entry))
                assertions.append(Assertion(label=a_label, kind=kind, summary=summary))

    assertions.sort(key=lambda a: a.label)

    # Validation statuses
    statuses: List[ValidationStatus] = []
    val_obj = dict_.get("validation") or {}
    status_list = val_obj.get("status") if isinstance(val_obj, dict) else dict_.get("validation_status")
    if isinstance(status_list, list):
        for st in status_list:
            if isinstance(st, dict) and "code" in st:
                code = st["code"]
                statuses.append(
                    ValidationStatus(
                        code=code,
                        explanation=st.get("explanation"),
                        url=st.get("url"),
                        severity=_classify_severity(code)
                    )
                )
    elif isinstance(dict_.get("validationResults"), dict):
        val_results = dict_["validationResults"]
        for cat in ("failure", "informational", "success"):
            cat_list = val_results.get(cat)
            if isinstance(cat_list, list):
                for item in cat_list:
                    if isinstance(item, dict) and "code" in item:
                        code = item["code"]
                        sev = _classify_severity(code)
                        if cat == "failure":
                            sev = Severity.ERROR
                        elif cat in ("informational", "success"):
                            sev = Severity.INFO
                        statuses.append(
                            ValidationStatus(
                                code=code,
                                explanation=item.get("explanation"),
                                url=item.get("url"),
                                severity=sev
                            )
                        )

    return Manifest(
        label=label,
        title=title,
        format=format_,
        claim_generator=claim_generator,
        is_update_manifest=is_update,
        signature=signature,
        assertions=assertions,
        validation_statuses=statuses
    )


def _summarize_assertion(label: str, value: Any) -> Optional[str]:
    if not isinstance(value, dict):
        return None

    # 1. Actions assertion
    actions = value.get("actions")
    if isinstance(actions, list):
        names = []
        for a in actions:
            if isinstance(a, dict) and a.get("action"):
                action = a["action"]
                dst = a.get("digitalSourceType") or a.get("digital_source_type")
                if dst and isinstance(dst, str):
                    clean_dst = dst.split("/")[-1]
                    names.append(f"{action} ({clean_dst})")
                else:
                    names.append(action)
        if names:
            return ", ".join(names)

    # 2. Data hash assertion
    if "hash_value" in value:
        hv = str(value["hash_value"])
        return f"hash: {hv[:16]}…"

    # 3. AI Training and Mining assertion
    if "training-mining" in label or "data-mining" in label:
        entries = value.get("entries")
        if isinstance(entries, dict):
            formatted = []
            for k in sorted(entries.keys()):
                val = entries[k]
                short_key = k.removeprefix("c2pa.").removeprefix("cawg.")
                if isinstance(val, dict) and "use" in val:
                    formatted.append(f"{short_key}={val['use']}")
                elif isinstance(val, str):
                    formatted.append(f"{short_key}={val}")
            if formatted:
                return f"AI Training: {', '.join(formatted)}"
        elif "use" in value:
            return f"AI Training: {value['use']}"

    # 4. Digital Source Type assertion
    if "digital_source_type" in label or "digitalSourceType" in label:
        type_val = value.get("digital_source_type") or value.get("digitalSourceType") or value.get("type")
        if type_val and isinstance(type_val, str):
            return type_val.split("/")[-1]

    # 5. AI Generative Info assertion
    if "generative" in label or "inference" in label:
        model = value.get("model")
        if isinstance(model, dict):
            name = model.get("name")
            ver = model.get("version")
            if name and ver:
                return f"model: {name} {ver}"
            elif name:
                return f"model: {name}"
        if "model_name" in value:
            return f"model: {value['model_name']}"
        if "prompt" in value:
            return f"prompt: {value['prompt']}"

    return None
