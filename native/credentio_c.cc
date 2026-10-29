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
#include <vector>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"
#include "claim/local_signer.h"
#include "crypto/crypto_read_handler.h"
#include "crypto/crypto_write_handler.h"
#include "crypto/default/default_crypto_read_handler.h"
#include "crypto/default/hasher.h"
#include "crypto/default/pem.h"
#include "crypto/hash.h"
#include "crypto/templated_crypto_write_handler.h"
#include "formats/bmff/writer.h"
#include "formats/gif/writer.h"
#include "formats/id3/writer.h"
#include "formats/jpeg/writer.h"
#include "formats/pdf/writer.h"
#include "formats/png/writer.h"
#include "formats/riff/writer.h"
#include "formats/tiff/writer.h"
#include "formats/zip/writer.h"
#include "generator/generator.h"
#include "generator/generator_factory.h"
#include "generator/generator_options.h"
#include "nlohmann/json.hpp"
#include "proto/generator.pb.h"
#include "riegeli/bytes/cfile_reader.h"
#include "riegeli/bytes/cfile_writer.h"
#include "riegeli/bytes/reader.h"
#include "riegeli/bytes/string_reader.h"
#include "riegeli/bytes/string_writer.h"
#include "riegeli/bytes/writer.h"
#include "testing/local_key_crypto_write_handler.h"
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

struct cr_signer {
  credentio::LocalKeyCryptoWriteHandlerOptions crypto_options;
  std::string generator_name;
  std::string generator_version;

  std::string last_error;
  double last_internal_seconds = 0.0;
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

  // TIFF header (little-endian II* or big-endian MM*)
  if (length_read >= 4 &&
      ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00) ||
       (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A))) {
    return "image/tiff";
  }

  // ZIP / OOXML header (PK\x03\x04)
  if (length_read >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04) {
    return "application/zip";
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
    if (brand == "qt  ") return "video/quicktime";
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

  std::optional<absl::string_view> validator_media_type = media_type_opt;
  if (*validator_media_type == "application/zip") {
    // Credentio's CreateZipFormat registers OOXML MIME types (.docx, .pptx, .xlsx)
    // rather than "application/zip"; passing std::nullopt lets FormatRegistry::GetFormat(reader)
    // match via ZipAssessor::IsSupported(reader).
    validator_media_type = std::nullopt;
  }

  const auto start_time = std::chrono::high_resolution_clock::now();
  const auto result_status = v->validator->Validate(reader, validator_media_type);
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

  absl::StatusOr<nlohmann::json> crjson =
      credentio::ConvertToCrJson(*validation_result);
  if (!crjson.ok()) {
    return crjson.status();
  }

  return crjson->dump(2);
}

absl::Status BuildSignRequest(
    cr_signer* s,
    const char* digital_source_type,
    const char* custom_assertions_json,
    credentio::GenerateManifestStoreRequest* request) {
  auto* created = request->mutable_actions()->mutable_created();
  if (digital_source_type && strlen(digital_source_type) > 0) {
    created->set_digital_source_type(digital_source_type);
  }
  auto* agent = created->mutable_action_metadata()->mutable_software_agent();
  agent->set_name(s->generator_name);
  if (!s->generator_version.empty()) {
    agent->set_version(s->generator_version);
  }

  if (custom_assertions_json && strlen(custom_assertions_json) > 0) {
    nlohmann::json parsed =
        nlohmann::json::parse(custom_assertions_json, nullptr, /*allow_exceptions=*/false);
    if (parsed.is_discarded()) {
      return absl::InvalidArgumentError("Invalid JSON in custom_assertions_json");
    }
    if (parsed.is_object()) {
      for (auto it = parsed.begin(); it != parsed.end(); ++it) {
        if (it.key().empty()) {
          return absl::InvalidArgumentError("Custom assertion label cannot be empty");
        }
        auto* ga = request->add_gathered_assertions();
        ga->set_label(it.key());
        ga->set_data(it.value().dump());
        ga->set_content_type(credentio::GatheredAssertion::CONTENT_TYPE_JSON);
      }
    } else if (parsed.is_array()) {
      for (const auto& item : parsed) {
        if (!item.is_object() || !item.contains("label") || !item["label"].is_string() ||
            !item.contains("data")) {
          return absl::InvalidArgumentError(
              "Custom assertions array items must be objects with 'label' and 'data'");
        }
        std::string label = item["label"].get<std::string>();
        if (label.empty()) {
          return absl::InvalidArgumentError("Custom assertion label cannot be empty");
        }
        auto* ga = request->add_gathered_assertions();
        ga->set_label(std::move(label));
        ga->set_data(item["data"].dump());
        ga->set_content_type(credentio::GatheredAssertion::CONTENT_TYPE_JSON);
      }
    } else {
      return absl::InvalidArgumentError(
          "custom_assertions_json must be a JSON object or array");
    }
  }

  return absl::OkStatus();
}

absl::Status SignReaderToWriter(
    cr_signer* s,
    riegeli::Reader& source,
    riegeli::Writer& destination,
    absl::string_view media_type,
    const char* digital_source_type,
    const char* custom_assertions_json) {
  credentio::GenerateManifestStoreRequest request;
  absl::Status req_status =
      BuildSignRequest(s, digital_source_type, custom_assertions_json, &request);
  if (!req_status.ok()) {
    return req_status;
  }

  auto crypto_write_handler =
      credentio::CreateLocalKeyCryptoWriteHandler(s->crypto_options);
  if (!crypto_write_handler.ok()) {
    return crypto_write_handler.status();
  }

  const credentio::HasherFactory& hash_factory = credentio::DefaultHasherFactory();
  credentio::TemplatedHasherFactory template_hash_factory(hash_factory.algorithm());
  credentio::TemplatedCryptoWriteHandler template_crypto_write_handler(
      crypto_write_handler->get());

  credentio::LocalClaimSigner template_claim_signer(&template_crypto_write_handler,
                                                    &template_hash_factory);
  credentio::LocalClaimSigner signing_claim_signer(crypto_write_handler->get(),
                                                   &hash_factory);

  credentio::GeneratorOptions generator_options;
  generator_options.generator_info.set_name(s->generator_name);
  if (!s->generator_version.empty()) {
    generator_options.generator_info.set_version(s->generator_version);
  }
  generator_options.signing_claim_signer = &signing_claim_signer;
  generator_options.template_claim_signer = &template_claim_signer;
  generator_options.hash_factory = &hash_factory;

  auto generator = credentio::CreateGenerator(std::move(generator_options));
  if (!generator.ok()) {
    return generator.status();
  }

  const auto start_time = std::chrono::high_resolution_clock::now();
  absl::Status write_status;

  if (media_type == "image/png") {
    credentio::PngWriter writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination,
                                /*output_metadata=*/nullptr);
  } else if (media_type == "image/jpeg") {
    credentio::JpegWriter writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination,
                                /*output_metadata=*/nullptr);
  } else if (media_type == "image/gif") {
    credentio::GifWriter writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination,
                                /*output_metadata=*/nullptr);
  } else if (media_type == "video/mp4" || media_type == "video/quicktime" ||
             media_type == "image/heic" || media_type == "image/heif" ||
             media_type == "image/avif" || media_type == "audio/mp4") {
    credentio::BmffWriter writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination,
                                /*output_metadata=*/nullptr);
  } else if (media_type == "image/tiff" || media_type == "image/tiff-fx" ||
             media_type == "image/x-adobe-dng") {
    credentio::TiffWriter writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination,
                                /*output_metadata=*/nullptr);
  } else if (media_type == "image/webp" || media_type == "audio/wav" ||
             media_type == "audio/x-wav" || media_type == "audio/vnd.wave" ||
             media_type == "video/x-msvideo" || media_type == "video/avi") {
    credentio::RiffWriter writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination,
                                /*output_metadata=*/nullptr);
  } else if (media_type == "audio/mpeg" || media_type == "audio/mp3" ||
             media_type == "audio/flac" || media_type == "audio/x-flac") {
    credentio::Id3Writer writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination);
  } else if (media_type == "application/pdf") {
    credentio::PdfWriter writer(generator->get());
    write_status = writer.Write(std::move(request), &source, &destination);
  } else if (media_type == "application/zip" ||
             media_type ==
                 "application/"
                 "vnd.openxmlformats-officedocument.presentationml.presentation" ||
             media_type ==
                 "application/"
                 "vnd.openxmlformats-officedocument.wordprocessingml.document" ||
             media_type ==
                 "application/"
                 "vnd.openxmlformats-officedocument.spreadsheetml.sheet") {
    credentio::ZipWriter writer(generator->get());
    write_status = writer.Write(request, &source, &destination);
  } else {
    write_status = absl::UnimplementedError(
        absl::StrCat("Unsupported media type for signing: ", media_type));
  }

  const auto end_time = std::chrono::high_resolution_clock::now();
  const std::chrono::duration<double> diff = end_time - start_time;
  s->last_internal_seconds = diff.count();

  return write_status;
}

int MapStatusToCode(const absl::Status& status) {
  if (status.ok()) return CR_STATUS_OK;
  switch (status.code()) {
    case absl::StatusCode::kInvalidArgument:
      return CR_STATUS_INVALID_ARGUMENT;
    case absl::StatusCode::kUnimplemented:
      return CR_STATUS_UNSUPPORTED_FORMAT;
    case absl::StatusCode::kNotFound:
    case absl::StatusCode::kPermissionDenied:
      return CR_STATUS_IO_ERROR;
    default:
      return CR_STATUS_INTERNAL_ERROR;
  }
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
    if (sniffed.has_value() && *sniffed != "application/zip") {
      resolved_media_type = std::move(sniffed);
    } else {
      auto mt = credentio::MediaType(file_path);
      if (mt.ok()) {
        resolved_media_type = *mt;
      } else if (sniffed.has_value()) {
        resolved_media_type = std::move(sniffed);
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

cr_signer* cr_signer_create(
    const char* claim_signer_key_pem,
    const char* claim_signer_cert_pem,
    const char* tsa_key_pem,
    const char* tsa_cert_pem,
    const char* generator_name,
    const char* generator_version) {
  if (!claim_signer_key_pem || strlen(claim_signer_key_pem) == 0 ||
      !claim_signer_cert_pem || strlen(claim_signer_cert_pem) == 0) {
    return nullptr;
  }

  auto s = std::make_unique<cr_signer>();
  s->crypto_options.claim_signer.key_pem = claim_signer_key_pem;

  auto cert_chain = credentio::LoadCertsFromPem(claim_signer_cert_pem);
  if (!cert_chain.ok() || cert_chain->empty()) {
    return nullptr;
  }
  s->crypto_options.claim_signer.certificate_chain = *std::move(cert_chain);

  const bool has_tsa_key = (tsa_key_pem && strlen(tsa_key_pem) > 0);
  const bool has_tsa_cert = (tsa_cert_pem && strlen(tsa_cert_pem) > 0);
  if (has_tsa_key != has_tsa_cert) {
    return nullptr;
  }

  if (has_tsa_key && has_tsa_cert) {
    s->crypto_options.disable_timestamping = false;
    s->crypto_options.tsa.key_pem = tsa_key_pem;
    s->crypto_options.tsa.cert_pem = tsa_cert_pem;
  } else {
    s->crypto_options.disable_timestamping = true;
  }

  s->generator_name =
      (generator_name && strlen(generator_name) > 0) ? generator_name : "Credentio";
  s->generator_version =
      (generator_version && strlen(generator_version) > 0) ? generator_version : "0.2.2";

  // Validate that the key and certificate chain can initialize a write handler
  auto test_handler = credentio::CreateLocalKeyCryptoWriteHandler(s->crypto_options);
  if (!test_handler.ok()) {
    return nullptr;
  }

  return s.release();
}

void cr_signer_free(cr_signer* signer) {
  delete signer;
}

int cr_sign_file(
    cr_signer* signer,
    const char* input_path,
    const char* output_path,
    const char* media_type,
    const char* digital_source_type,
    const char* custom_assertions_json) {
  if (!signer || !input_path || !output_path) {
    if (signer) signer->last_error = "Null argument passed to cr_sign_file";
    return CR_STATUS_INVALID_ARGUMENT;
  }

  signer->last_error.clear();
  signer->last_internal_seconds = 0.0;

  if (strcmp(input_path, output_path) == 0) {
    signer->last_error =
        "In-place signing is not supported; output_path must differ from input_path";
    return CR_STATUS_INVALID_ARGUMENT;
  }

  riegeli::CFileReader<> source(input_path);
  if (!source.ok()) {
    signer->last_error = absl::StrCat("Failed to open input file: ", source.status().message());
    return CR_STATUS_IO_ERROR;
  }

  std::optional<std::string> resolved_media_type;
  if (media_type && strlen(media_type) > 0) {
    resolved_media_type = media_type;
  } else {
    auto mt = credentio::MediaType(input_path);
    if (mt.ok()) {
      resolved_media_type = *mt;
    } else {
      auto sniffed = SniffMediaType(source);
      if (sniffed.has_value()) {
        resolved_media_type = std::move(sniffed);
      }
    }
  }

  if (!resolved_media_type.has_value()) {
    signer->last_error = "Could not determine media type of input asset";
    return CR_STATUS_INVALID_ARGUMENT;
  }

  riegeli::CFileWriter<> destination(
      output_path, riegeli::CFileWriterBase::Options().set_read(true));
  if (!destination.ok()) {
    signer->last_error =
        absl::StrCat("Failed to open output file: ", destination.status().message());
    return CR_STATUS_IO_ERROR;
  }

  absl::Status status = SignReaderToWriter(
      signer, source, destination, *resolved_media_type, digital_source_type,
      custom_assertions_json);
  if (!status.ok()) {
    signer->last_error = std::string(status.message());
    return MapStatusToCode(status);
  }

  if (!source.Close()) {
    signer->last_error = std::string(source.status().message());
    return CR_STATUS_IO_ERROR;
  }
  if (!destination.Close()) {
    signer->last_error = std::string(destination.status().message());
    return CR_STATUS_IO_ERROR;
  }

  return CR_STATUS_OK;
}

uint8_t* cr_sign_bytes(
    cr_signer* signer,
    const uint8_t* bytes,
    size_t count,
    const char* media_type,
    const char* digital_source_type,
    const char* custom_assertions_json,
    size_t* out_size,
    int* out_status) {
  if (out_size) *out_size = 0;
  if (!signer || !bytes || count == 0 || !out_size) {
    if (signer) signer->last_error = "Invalid arguments passed to cr_sign_bytes";
    if (out_status) *out_status = CR_STATUS_INVALID_ARGUMENT;
    return nullptr;
  }

  signer->last_error.clear();
  signer->last_internal_seconds = 0.0;

  absl::string_view bytes_view(reinterpret_cast<const char*>(bytes), count);
  riegeli::StringReader<> source(bytes_view);

  std::optional<std::string> resolved_media_type;
  if (media_type && strlen(media_type) > 0) {
    resolved_media_type = media_type;
  } else {
    auto sniffed = SniffMediaType(source);
    if (sniffed.has_value()) {
      resolved_media_type = std::move(sniffed);
    }
  }

  if (!resolved_media_type.has_value()) {
    signer->last_error = "Media type could not be determined from bytes";
    if (out_status) *out_status = CR_STATUS_INVALID_ARGUMENT;
    return nullptr;
  }

  std::string dest_bytes;
  riegeli::StringWriter<> destination(&dest_bytes);

  absl::Status status = SignReaderToWriter(
      signer, source, destination, *resolved_media_type, digital_source_type,
      custom_assertions_json);
  if (!status.ok()) {
    signer->last_error = std::string(status.message());
    if (out_status) *out_status = MapStatusToCode(status);
    return nullptr;
  }

  if (!source.Close() || !destination.Close()) {
    signer->last_error = "Failed to flush in-memory asset writer";
    if (out_status) *out_status = CR_STATUS_IO_ERROR;
    return nullptr;
  }

  uint8_t* copy = static_cast<uint8_t*>(malloc(dest_bytes.size()));
  if (!copy) {
    signer->last_error = "Out of memory allocating signed asset buffer";
    if (out_status) *out_status = CR_STATUS_INTERNAL_ERROR;
    return nullptr;
  }
  memcpy(copy, dest_bytes.data(), dest_bytes.size());
  *out_size = dest_bytes.size();
  if (out_status) *out_status = CR_STATUS_OK;
  return copy;
}

const char* cr_signer_last_error(cr_signer* signer) {
  if (!signer) return "Null signer";
  return signer->last_error.c_str();
}

double cr_signer_last_internal_seconds(cr_signer* signer) {
  if (!signer) return 0.0;
  return signer->last_internal_seconds;
}

void cr_string_free(char* str) {
  free(str);
}

void cr_bytes_free(uint8_t* bytes) {
  free(bytes);
}

const char* cr_version(void) {
  return "0.2.2-credentio-c";
}

}  // extern "C"
