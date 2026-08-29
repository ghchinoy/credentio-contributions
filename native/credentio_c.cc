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

#include "credentio_c.h"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <utility>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"
#include "crypto/crypto_read_handler.h"
#include "crypto/default/default_crypto_read_handler.h"
#include "formats/core_registry.h"
#include "nlohmann/json.hpp"
#include "riegeli/bytes/cfile_reader.h"
#include "riegeli/bytes/string_reader.h"
#include "utils/crjson.h"
#include "utils/media_type.h"
#include "validator/asset_validator_impl.h"
#include "validator/result.h"
#include "validator/validator_options.h"

struct cr_validator {
  std::string claim_signer_trust_pem;
  std::string tsa_trust_pem;
  bool skip_trust_checks = false;

  std::string last_error;
  double last_internal_seconds = 0.0;

  std::unique_ptr<credentio::AssetValidatorImpl> validator;
};

namespace {

char* DuplicateString(const std::string& str) {
  char* copy = static_cast<char*>(malloc(str.size() + 1));
  if (!copy) return nullptr;
  memcpy(copy, str.c_str(), str.size() + 1);
  return copy;
}

std::optional<std::string> SniffMediaType(riegeli::Reader& reader) {
  if (!reader.Seek(0) || reader.pos() != 0) {
    return std::nullopt;
  }
  char buf[32];
  size_t length_read = 0;
  if (!reader.Read(32, buf, &length_read) || length_read < 4) {
    reader.Seek(0);
    return std::nullopt;
  }
  reader.Seek(0);

  const uint8_t* b = reinterpret_cast<const uint8_t*>(buf);

  // ID3 tag header (MP3 / MPEG audio container)
  if (length_read >= 3 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    return "audio/mpeg";
  }

  // FLAC header
  if (length_read >= 4 && b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43) {
    return "audio/flac";
  }

  // JPEG header
  if (length_read >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return "image/jpeg";
  }

  // PNG header
  if (length_read >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 &&
      b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) {
    return "image/png";
  }

  // GIF header
  if (length_read >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38 &&
      (b[4] == 0x37 || b[4] == 0x39) && b[5] == 0x61) {
    return "image/gif";
  }

  // PDF header
  if (length_read >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) {
    return "application/pdf";
  }

  // RIFF container
  if (length_read >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) {
    absl::string_view form(buf + 8, 4);
    if (form == "WAVE") return "audio/wav";
    if (form == "WEBP") return "image/webp";
    if (form == "AVI ") return "video/x-msvideo";
  }

  // ISOBMFF / ftyp box
  if (length_read >= 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    absl::string_view brand(buf + 8, 4);
    if (brand == "avif" || brand == "avis") return "image/avif";
    if (brand == "heic" || brand == "heix" || brand == "mif1") return "image/heic";
    if (brand == "M4A ") return "audio/mp4";
    return "video/mp4";
  }

  return std::nullopt;
}

absl::StatusOr<std::string> ValidateReaderAndGenerateCrJson(
    cr_validator* v,
    riegeli::Reader& reader,
    std::optional<absl::string_view> media_type_opt) {
  if (!media_type_opt.has_value()) {
    return absl::InvalidArgumentError("Media type could not be determined");
  }

  const auto start_time = std::chrono::high_resolution_clock::now();
  const auto result_status = v->validator->Validate(reader, media_type_opt);
  const auto end_time = std::chrono::high_resolution_clock::now();

  const std::chrono::duration<double> diff = end_time - start_time;
  v->last_internal_seconds = diff.count();

  if (!result_status.ok()) {
    return result_status.status();
  }

  const auto& validation_result = *result_status;
  if (!validation_result) {
    return absl::NotFoundError("No C2PA validation result produced");
  }

  auto registry = credentio::CreateCoreFormatRegistry();
  auto format = registry->GetFormat(*media_type_opt);
  if (!format.ok()) {
    return format.status();
  }

  if (!reader.Seek(0) || reader.pos() != 0) {
    return absl::DataLossError("Failed to seek to start of asset reader");
  }

  auto manifest_store = (*format)->extractor()->ExtractManifestStore(reader);
  if (!manifest_store.ok()) {
    return manifest_store.status();
  }

  absl::StatusOr<nlohmann::json> crjson =
      credentio::ConvertToCrJson(*manifest_store, validation_result->proto());
  if (!crjson.ok()) {
    return crjson.status();
  }

  return crjson->dump(2);
}

}  // namespace

extern "C" {

cr_validator* cr_validator_create(
    const char* claim_signer_trust_pem,
    const char* tsa_trust_pem,
    int skip_trust_checks) {
  auto v = std::make_unique<cr_validator>();
  if (claim_signer_trust_pem) {
    v->claim_signer_trust_pem = claim_signer_trust_pem;
  }
  if (tsa_trust_pem) {
    v->tsa_trust_pem = tsa_trust_pem;
  }
  v->skip_trust_checks = (skip_trust_checks != 0);

  credentio::DefaultCryptoReadHandlerOptions crypto_options;
  if (!v->claim_signer_trust_pem.empty()) {
    crypto_options.claim_signer_trust_anchors_pem = v->claim_signer_trust_pem;
  } else {
    crypto_options.skip_claim_signer_trust_checks_for_test = true;
  }

  if (!v->tsa_trust_pem.empty()) {
    crypto_options.tsa_trust_anchors_pem = v->tsa_trust_pem;
  } else {
    crypto_options.skip_tsa_trust_checks_for_test = true;
  }

  if (v->skip_trust_checks) {
    crypto_options.skip_claim_signer_trust_checks_for_test = true;
    crypto_options.skip_tsa_trust_checks_for_test = true;
  }

  auto crypto_read_handler = credentio::CreateDefaultCryptoReadHandler(crypto_options);
  if (!crypto_read_handler.ok()) {
    return nullptr;
  }

  v->validator = std::make_unique<credentio::AssetValidatorImpl>(credentio::ValidatorOptions{
      .crypto_read_handler = *std::move(crypto_read_handler),
  });

  return v.release();
}

void cr_validator_free(cr_validator* validator) {
  delete validator;
}

char* cr_validate_file(
    cr_validator* validator,
    const char* file_path,
    const char* media_type,
    int* out_status) {
  if (!validator || !file_path) {
    if (out_status) *out_status = CR_STATUS_INVALID_ARGUMENT;
    return nullptr;
  }

  validator->last_error.clear();
  validator->last_internal_seconds = 0.0;

  riegeli::CFileReader<> reader(file_path);
  if (!reader.ok()) {
    validator->last_error = absl::StrCat("Failed to open file: ", reader.status().message());
    if (out_status) *out_status = CR_STATUS_IO_ERROR;
    return nullptr;
  }

  std::optional<std::string> resolved_media_type;
  if (media_type && strlen(media_type) > 0) {
    resolved_media_type = media_type;
  } else {
    auto sniffed = SniffMediaType(reader);
    if (sniffed.has_value()) {
      resolved_media_type = std::move(sniffed);
    } else {
      auto mt = credentio::MediaType(file_path);
      if (mt.ok()) {
        resolved_media_type = *mt;
      }
    }
  }

  std::optional<absl::string_view> media_type_opt;
  if (resolved_media_type.has_value()) {
    media_type_opt = *resolved_media_type;
  }

  auto json_result = ValidateReaderAndGenerateCrJson(validator, reader, media_type_opt);
  if (!json_result.ok()) {
    validator->last_error = std::string(json_result.status().message());
    const auto code = json_result.status().code();
    if (code == absl::StatusCode::kNotFound || code == absl::StatusCode::kInvalidArgument) {
      if (out_status) *out_status = CR_STATUS_NO_CREDENTIALS;
    } else {
      if (out_status) *out_status = CR_STATUS_INTERNAL_ERROR;
    }
    return nullptr;
  }

  if (out_status) *out_status = CR_STATUS_OK;
  return DuplicateString(*json_result);
}

char* cr_validate_bytes(
    cr_validator* validator,
    const uint8_t* bytes,
    size_t count,
    const char* media_type,
    int* out_status) {
  if (!validator || !bytes || count == 0) {
    if (out_status) *out_status = CR_STATUS_INVALID_ARGUMENT;
    return nullptr;
  }

  validator->last_error.clear();
  validator->last_internal_seconds = 0.0;

  absl::string_view bytes_view(reinterpret_cast<const char*>(bytes), count);
  riegeli::StringReader<> reader(bytes_view);

  std::optional<std::string> resolved_media_type;
  if (media_type && strlen(media_type) > 0) {
    resolved_media_type = media_type;
  } else {
    auto sniffed = SniffMediaType(reader);
    if (sniffed.has_value()) {
      resolved_media_type = std::move(sniffed);
    }
  }

  std::optional<absl::string_view> media_type_opt;
  if (resolved_media_type.has_value()) {
    media_type_opt = *resolved_media_type;
  }

  auto json_result = ValidateReaderAndGenerateCrJson(validator, reader, media_type_opt);
  if (!json_result.ok()) {
    validator->last_error = std::string(json_result.status().message());
    const auto code = json_result.status().code();
    if (code == absl::StatusCode::kNotFound || code == absl::StatusCode::kInvalidArgument) {
      if (out_status) *out_status = CR_STATUS_NO_CREDENTIALS;
    } else {
      if (out_status) *out_status = CR_STATUS_INTERNAL_ERROR;
    }
    return nullptr;
  }

  if (out_status) *out_status = CR_STATUS_OK;
  return DuplicateString(*json_result);
}

const char* cr_last_error(cr_validator* validator) {
  if (!validator) return "Null validator";
  return validator->last_error.c_str();
}

double cr_last_internal_seconds(cr_validator* validator) {
  if (!validator) return 0.0;
  return validator->last_internal_seconds;
}

void cr_string_free(char* str) {
  free(str);
}

const char* cr_version(void) {
  return "0.1.0-credentio-c";
}

}  // extern "C"
