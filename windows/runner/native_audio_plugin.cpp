#include "native_audio_plugin.h"

#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <string>
#include <tlhelp32.h>
#include <vector>

namespace {

constexpr uint32_t kTargetSampleRate = 24000;
constexpr size_t kTargetChunkBytes = 640;
constexpr DWORD kActivationTimeoutMs = 5000;
constexpr UINT kAudioChunkMessage = WM_APP + 100;
constexpr wchar_t kNativeAudioWindowClassName[] = L"FaceAgentNativeAudioWindow";

int16_t FloatToPcm16(float sample) {
  const float clamped = std::clamp(sample, -1.0f, 1.0f);
  const int sample_16 = static_cast<int>(std::lround(clamped * 32767.0f));
  return static_cast<int16_t>(std::clamp(sample_16, -32768, 32767));
}

class AudioInterfaceActivator
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          IActivateAudioInterfaceCompletionHandler> {
 public:
  AudioInterfaceActivator() : completed_event_(CreateEvent(nullptr, FALSE, FALSE, nullptr)) {}

  ~AudioInterfaceActivator() override {
    if (completed_event_ != nullptr) {
      CloseHandle(completed_event_);
    }
  }

  IFACEMETHODIMP ActivateCompleted(
      IActivateAudioInterfaceAsyncOperation* activate_operation) override {
    if (activate_operation == nullptr) {
      activation_result_ = E_POINTER;
    } else {
      Microsoft::WRL::ComPtr<IUnknown> activated_interface;
      HRESULT operation_result = E_FAIL;
      const HRESULT hr = activate_operation->GetActivateResult(
          &operation_result, activated_interface.GetAddressOf());
      activation_result_ = SUCCEEDED(hr) ? operation_result : hr;
      if (SUCCEEDED(activation_result_)) {
        activated_interface_ = activated_interface;
      }
    }

    if (completed_event_ != nullptr) {
      SetEvent(completed_event_);
    }
    return S_OK;
  }

  HRESULT WaitForCompletion(Microsoft::WRL::ComPtr<IAudioClient>* audio_client) {
    if (completed_event_ == nullptr) {
      return E_HANDLE;
    }

    const DWORD wait_result =
        WaitForSingleObject(completed_event_, kActivationTimeoutMs);
    if (wait_result != WAIT_OBJECT_0) {
      return HRESULT_FROM_WIN32(wait_result == WAIT_TIMEOUT ? ERROR_TIMEOUT
                                                            : ERROR_GEN_FAILURE);
    }
    if (FAILED(activation_result_)) {
      return activation_result_;
    }
    audio_client->Reset();
    return activated_interface_.As(audio_client);
  }

 private:
  HANDLE completed_event_ = nullptr;
  HRESULT activation_result_ = E_FAIL;
  Microsoft::WRL::ComPtr<IUnknown> activated_interface_;
};

}  // namespace

WasapiLoopbackCapture::WasapiLoopbackCapture() = default;

WasapiLoopbackCapture::~WasapiLoopbackCapture() {
  Stop();
}

bool WasapiLoopbackCapture::Start(AudioCallback callback,
                                  CaptureMode mode,
                                  DWORD target_process_id,
                                  std::string* error_message) {
  if (is_recording_) {
    return true;
  }

  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }

  if (!callback) {
    if (error_message != nullptr) {
      *error_message = "Audio callback is missing";
    }
    return false;
  }

  callback_ = std::move(callback);
  capture_mode_ = mode;
  target_process_id_ = target_process_id;
  stop_requested_ = false;
  is_recording_ = true;
  ResetResamplerState();

  try {
    capture_thread_ = std::thread([this]() { CaptureLoop(); });
  } catch (...) {
    is_recording_ = false;
    callback_ = nullptr;
    if (error_message != nullptr) {
      *error_message = "Failed to create capture thread";
    }
    return false;
  }

  return true;
}

void WasapiLoopbackCapture::Stop() {
  stop_requested_ = true;

  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }

  is_recording_ = false;
  callback_ = nullptr;
  ResetResamplerState();
}

void WasapiLoopbackCapture::ResetResamplerState() {
  mono_resample_buffer_.clear();
  pending_pcm_bytes_.clear();
  resample_cursor_ = 0.0;
}

void WasapiLoopbackCapture::CaptureLoop() {
  const HRESULT coinit_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  HRESULT hr = coinit_hr;
  const bool com_initialized = SUCCEEDED(coinit_hr) || coinit_hr == RPC_E_CHANGED_MODE;

  if (FAILED(coinit_hr) && coinit_hr != RPC_E_CHANGED_MODE) {
    is_recording_ = false;
    return;
  }

  Microsoft::WRL::ComPtr<IMMDeviceEnumerator> device_enumerator;
  Microsoft::WRL::ComPtr<IMMDevice> device;
  Microsoft::WRL::ComPtr<IAudioClient> audio_client;
  Microsoft::WRL::ComPtr<IAudioCaptureClient> capture_client;
  Microsoft::WRL::ComPtr<IActivateAudioInterfaceAsyncOperation> activation_op;
  WAVEFORMATEX* mix_format = nullptr;
  HANDLE sample_ready_event = nullptr;

  auto cleanup = [&]() {
    if (audio_client) {
      audio_client->Stop();
    }
    if (sample_ready_event != nullptr) {
      CloseHandle(sample_ready_event);
    }
    if (mix_format != nullptr) {
      CoTaskMemFree(mix_format);
    }
    if (com_initialized && coinit_hr != RPC_E_CHANGED_MODE) {
      CoUninitialize();
    }
    is_recording_ = false;
  };

  if (capture_mode_ == CaptureMode::kMicrophone ||
      capture_mode_ == CaptureMode::kSystemLoopback) {
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          IID_PPV_ARGS(&device_enumerator));
    if (FAILED(hr)) {
      cleanup();
      return;
    }

    hr = device_enumerator->GetDefaultAudioEndpoint(
        capture_mode_ == CaptureMode::kMicrophone ? eCapture : eRender,
        eConsole, &device);
    if (FAILED(hr)) {
      cleanup();
      return;
    }

    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(audio_client.GetAddressOf()));
    if (FAILED(hr)) {
      cleanup();
      return;
    }
  } else {
    if (target_process_id_ == 0) {
      cleanup();
      return;
    }

    AUDIOCLIENT_ACTIVATION_PARAMS activation_params = {};
    activation_params.ActivationType =
        AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
    activation_params.ProcessLoopbackParams.TargetProcessId =
        target_process_id_;
    activation_params.ProcessLoopbackParams.ProcessLoopbackMode =
        PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;

    PROPVARIANT activation_prop = {};
    activation_prop.vt = VT_BLOB;
    activation_prop.blob.cbSize = sizeof(activation_params);
    activation_prop.blob.pBlobData =
        reinterpret_cast<BYTE*>(&activation_params);

    auto completion_handler =
        Microsoft::WRL::Make<AudioInterfaceActivator>();
    if (!completion_handler) {
      cleanup();
      return;
    }

    hr = ActivateAudioInterfaceAsync(
        VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
        &activation_prop, completion_handler.Get(),
        activation_op.GetAddressOf());
    if (FAILED(hr)) {
      cleanup();
      return;
    }

    hr = completion_handler->WaitForCompletion(&audio_client);
    if (FAILED(hr)) {
      cleanup();
      return;
    }
  }

  hr = audio_client->GetMixFormat(&mix_format);
  if (FAILED(hr) || mix_format == nullptr) {
    cleanup();
    return;
  }

  input_sample_rate_ = mix_format->nSamplesPerSec;
  block_align_ = mix_format->nBlockAlign;
  channel_count_ = mix_format->nChannels;
  bits_per_sample_ = mix_format->wBitsPerSample;
  input_is_float_ = false;

  if (mix_format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) {
    input_is_float_ = true;
  } else if (mix_format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
    const auto* extensible =
        reinterpret_cast<WAVEFORMATEXTENSIBLE*>(mix_format);
    if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
      input_is_float_ = true;
    } else if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
      input_is_float_ = false;
    } else {
      cleanup();
      return;
    }
  } else if (mix_format->wFormatTag != WAVE_FORMAT_PCM) {
    cleanup();
    return;
  }

  sample_ready_event = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  if (sample_ready_event == nullptr) {
    cleanup();
    return;
  }

  hr = audio_client->Initialize(
      AUDCLNT_SHAREMODE_SHARED,
      (capture_mode_ == CaptureMode::kSystemLoopback
           ? AUDCLNT_STREAMFLAGS_LOOPBACK
           : 0) |
          AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
      0, 0,
      mix_format, nullptr);
  if (FAILED(hr)) {
    cleanup();
    return;
  }

  hr = audio_client->SetEventHandle(sample_ready_event);
  if (FAILED(hr)) {
    cleanup();
    return;
  }

  hr = audio_client->GetService(IID_PPV_ARGS(&capture_client));
  if (FAILED(hr)) {
    cleanup();
    return;
  }

  hr = audio_client->Start();
  if (FAILED(hr)) {
    cleanup();
    return;
  }

  while (!stop_requested_) {
    const DWORD wait_result = WaitForSingleObject(sample_ready_event, 200);
    if (wait_result == WAIT_TIMEOUT) {
      continue;
    }
    if (wait_result != WAIT_OBJECT_0) {
      break;
    }

    UINT32 packet_frames = 0;
    hr = capture_client->GetNextPacketSize(&packet_frames);
    if (FAILED(hr)) {
      break;
    }

    while (packet_frames > 0) {
      BYTE* data = nullptr;
      UINT32 frames_available = 0;
      DWORD flags = 0;

      hr = capture_client->GetBuffer(&data, &frames_available, &flags, nullptr,
                                     nullptr);
      if (FAILED(hr)) {
        stop_requested_ = true;
        break;
      }

      const bool ok =
          ProcessAudioBuffer(data, frames_available,
                             (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0);

      capture_client->ReleaseBuffer(frames_available);

      if (!ok) {
        stop_requested_ = true;
        break;
      }

      hr = capture_client->GetNextPacketSize(&packet_frames);
      if (FAILED(hr)) {
        stop_requested_ = true;
        break;
      }
    }
  }

  FlushPendingChunks();
  cleanup();
}

bool WasapiLoopbackCapture::ProcessAudioBuffer(const uint8_t* data,
                                               size_t frame_count,
                                               bool silent) {
  if (channel_count_ == 0 || input_sample_rate_ == 0 || block_align_ == 0) {
    return false;
  }

  if (silent) {
    for (size_t i = 0; i < frame_count; ++i) {
      AppendMonoSample(0.0f);
    }
    FlushPendingChunks();
    return true;
  }

  for (size_t frame_index = 0; frame_index < frame_count; ++frame_index) {
    const uint8_t* frame_data = data + (frame_index * block_align_);
    float mono_sample = 0.0f;
    for (uint16_t channel = 0; channel < channel_count_; ++channel) {
      mono_sample += ReadSampleAsFloat(frame_data, channel);
    }
    mono_sample /= static_cast<float>(channel_count_);
    AppendMonoSample(mono_sample);
  }

  FlushPendingChunks();
  return true;
}

float WasapiLoopbackCapture::ReadSampleAsFloat(const uint8_t* frame_data,
                                               uint16_t channel_index) const {
  const size_t bytes_per_channel = block_align_ / channel_count_;
  const uint8_t* sample_ptr = frame_data + (channel_index * bytes_per_channel);

  if (input_is_float_ && bits_per_sample_ == 32) {
    float value = 0.0f;
    std::memcpy(&value, sample_ptr, sizeof(float));
    return value;
  }

  if (bits_per_sample_ == 16) {
    int16_t value = 0;
    std::memcpy(&value, sample_ptr, sizeof(int16_t));
    return static_cast<float>(value) / 32768.0f;
  }

  if (bits_per_sample_ == 24) {
    int32_t value = (static_cast<int32_t>(sample_ptr[0]) |
                     (static_cast<int32_t>(sample_ptr[1]) << 8) |
                     (static_cast<int32_t>(sample_ptr[2]) << 16));
    if ((value & 0x00800000) != 0) {
      value |= ~0x00FFFFFF;
    }
    return static_cast<float>(value) / 8388608.0f;
  }

  if (bits_per_sample_ == 32) {
    int32_t value = 0;
    std::memcpy(&value, sample_ptr, sizeof(int32_t));
    return static_cast<float>(value) / 2147483648.0f;
  }

  return 0.0f;
}

void WasapiLoopbackCapture::AppendMonoSample(float sample) {
  mono_resample_buffer_.push_back(sample);

  const double step = static_cast<double>(input_sample_rate_) /
                      static_cast<double>(kTargetSampleRate);

  while (resample_cursor_ + 1.0 < mono_resample_buffer_.size()) {
    const size_t left_index = static_cast<size_t>(resample_cursor_);
    const size_t right_index = left_index + 1;
    const double fraction = resample_cursor_ - static_cast<double>(left_index);
    const float left = mono_resample_buffer_[left_index];
    const float right = mono_resample_buffer_[right_index];
    const float interpolated =
        static_cast<float>(left + ((right - left) * fraction));

    const int16_t pcm16 = FloatToPcm16(interpolated);
    pending_pcm_bytes_.push_back(static_cast<uint8_t>(pcm16 & 0xFF));
    pending_pcm_bytes_.push_back(static_cast<uint8_t>((pcm16 >> 8) & 0xFF));

    resample_cursor_ += step;
  }

  const size_t max_consumable =
      mono_resample_buffer_.empty() ? 0 : mono_resample_buffer_.size() - 1;
  const size_t consumed =
      std::min(static_cast<size_t>(resample_cursor_), max_consumable);
  if (consumed > 1) {
    mono_resample_buffer_.erase(mono_resample_buffer_.begin(),
                                mono_resample_buffer_.begin() + consumed - 1);
    resample_cursor_ -= static_cast<double>(consumed - 1);
  }
}

void WasapiLoopbackCapture::FlushPendingChunks() {
  if (!callback_) {
    pending_pcm_bytes_.clear();
    return;
  }

  while (pending_pcm_bytes_.size() >= kTargetChunkBytes) {
    std::vector<uint8_t> chunk(pending_pcm_bytes_.begin(),
                               pending_pcm_bytes_.begin() + kTargetChunkBytes);
    callback_(chunk);
    pending_pcm_bytes_.erase(pending_pcm_bytes_.begin(),
                             pending_pcm_bytes_.begin() + kTargetChunkBytes);
  }
}

NativeAudioPlugin::NativeAudioPlugin(flutter::FlutterEngine* engine) {
  auto* messenger = engine->messenger();
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();

  control_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "native_audio/control", codec);
  pcm_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "native_audio/pcm", codec);

  control_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  pcm_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                     events) {
            std::lock_guard<std::mutex> lock(event_sink_mutex_);
            event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue* arguments) {
            std::lock_guard<std::mutex> lock(event_sink_mutex_);
            event_sink_.reset();
            return nullptr;
          }));

  CreateMessageWindow();
}

NativeAudioPlugin::~NativeAudioPlugin() {
  user_capture_.Stop();
  peer_capture_.Stop();
  DestroyMessageWindow();
}

void NativeAudioPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "setCaptureMode") {
    const auto* arguments = call.arguments();
    const auto* mode_value =
        arguments == nullptr ? nullptr : std::get_if<std::string>(arguments);
    if (mode_value == nullptr) {
      result->Error("INVALID_ARGS", "Expected a string capture mode");
      return;
    }

    if (*mode_value == "microphone") {
      capture_mode_ = WasapiLoopbackCapture::CaptureMode::kMicrophone;
    } else if (*mode_value == "chrome_process") {
      capture_mode_ = WasapiLoopbackCapture::CaptureMode::kProcessLoopback;
    } else {
      capture_mode_ = WasapiLoopbackCapture::CaptureMode::kSystemLoopback;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (call.method_name() == "startUserMicrophone") {
    std::string error_message;
    const bool started = user_capture_.Start(
        [this](const std::vector<uint8_t>& bytes) {
          SendAudioChunk("user_mic", bytes);
        },
        WasapiLoopbackCapture::CaptureMode::kMicrophone, 0, &error_message);
    if (started) {
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("START_FAILED",
                    error_message.empty() ? "Failed to start microphone capture"
                                          : error_message);
    }
    return;
  }

  if (call.method_name() == "stopUserMicrophone") {
    user_capture_.Stop();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (call.method_name() == "startPeerCapture" ||
      call.method_name() == "startRecording") {
    std::string error_message;
    DWORD target_process_id = 0;
    if (capture_mode_ == WasapiLoopbackCapture::CaptureMode::kProcessLoopback) {
      target_process_id =
          FindForegroundProcessIdByExecutableName(L"chrome.exe");
      if (target_process_id == 0) {
        target_process_id = FindRootProcessIdByExecutableName(L"chrome.exe");
      } else {
        target_process_id = FindChromeAncestorProcessId(target_process_id);
      }
      if (target_process_id == 0) {
        result->Error("PROCESS_NOT_FOUND",
                      "Chrome is not running, so app audio could not start");
        return;
      }
    }

    const bool started = peer_capture_.Start(
        [this](const std::vector<uint8_t>& bytes) {
          SendAudioChunk("peer_audio", bytes);
        },
        capture_mode_, target_process_id,
        &error_message);
    if (started) {
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("START_FAILED",
                    error_message.empty()
                        ? (capture_mode_ ==
                                   WasapiLoopbackCapture::CaptureMode::kProcessLoopback
                               ? "Failed to start Chrome audio capture"
                               : (capture_mode_ ==
                                          WasapiLoopbackCapture::CaptureMode::kMicrophone
                                      ? "Failed to start microphone capture"
                                      : "Failed to start system audio capture"))
                                          : error_message);
    }
    return;
  }

  if (call.method_name() == "stopPeerCapture" ||
      call.method_name() == "stopRecording") {
    peer_capture_.Stop();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  result->NotImplemented();
}

void NativeAudioPlugin::SendAudioChunk(const std::string& source,
                                       const std::vector<uint8_t>& bytes) {
  {
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    if (!event_sink_) {
      return;
    }
  }

  {
    std::lock_guard<std::mutex> lock(pending_audio_mutex_);
    pending_audio_chunks_.push(PendingAudioChunk{source, bytes});
  }

  if (message_window_ != nullptr) {
    PostMessage(message_window_, kAudioChunkMessage, 0, 0);
  }
}

void NativeAudioPlugin::DispatchPendingAudioChunks() {
  std::queue<PendingAudioChunk> chunks;
  {
    std::lock_guard<std::mutex> lock(pending_audio_mutex_);
    std::swap(chunks, pending_audio_chunks_);
  }

  std::lock_guard<std::mutex> lock(event_sink_mutex_);
  if (!event_sink_) {
    return;
  }

  while (!chunks.empty()) {
    flutter::EncodableMap event = {
        {flutter::EncodableValue("source"),
         flutter::EncodableValue(chunks.front().source)},
        {flutter::EncodableValue("pcm"),
         flutter::EncodableValue(chunks.front().bytes)},
    };
    event_sink_->Success(flutter::EncodableValue(event));
    chunks.pop();
  }
}

bool NativeAudioPlugin::CreateMessageWindow() {
  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = NativeAudioPlugin::MessageWindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kNativeAudioWindowClassName;

  RegisterClassW(&window_class);

  message_window_ = CreateWindowExW(
      0, kNativeAudioWindowClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
      nullptr, GetModuleHandle(nullptr), this);

  return message_window_ != nullptr;
}

void NativeAudioPlugin::DestroyMessageWindow() {
  if (message_window_ != nullptr) {
    DestroyWindow(message_window_);
    message_window_ = nullptr;
  }
}

LRESULT CALLBACK NativeAudioPlugin::MessageWindowProc(HWND hwnd, UINT message,
                                                      WPARAM wparam,
                                                      LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create_struct = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* plugin =
        reinterpret_cast<NativeAudioPlugin*>(create_struct->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(plugin));
    return TRUE;
  }

  auto* plugin = reinterpret_cast<NativeAudioPlugin*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (plugin != nullptr && message == kAudioChunkMessage) {
    plugin->DispatchPendingAudioChunks();
    return 0;
  }

  return DefWindowProcW(hwnd, message, wparam, lparam);
}

bool NativeAudioPlugin::IsProcessExecutableName(
    DWORD process_id,
    const std::wstring& executable_name) const {
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return false;
  }

  PROCESSENTRY32W process_entry = {};
  process_entry.dwSize = sizeof(process_entry);
  bool matches = false;

  if (Process32FirstW(snapshot, &process_entry)) {
    do {
      if (process_entry.th32ProcessID == process_id &&
          _wcsicmp(process_entry.szExeFile, executable_name.c_str()) == 0) {
        matches = true;
        break;
      }
    } while (Process32NextW(snapshot, &process_entry));
  }

  CloseHandle(snapshot);
  return matches;
}

DWORD NativeAudioPlugin::FindChromeAncestorProcessId(DWORD process_id) const {
  if (process_id == 0) {
    return 0;
  }

  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return process_id;
  }

  std::vector<PROCESSENTRY32W> processes;
  PROCESSENTRY32W process_entry = {};
  process_entry.dwSize = sizeof(process_entry);

  if (Process32FirstW(snapshot, &process_entry)) {
    do {
      processes.push_back(process_entry);
    } while (Process32NextW(snapshot, &process_entry));
  }

  CloseHandle(snapshot);

  DWORD current = process_id;
  DWORD ancestor = process_id;

  while (current != 0) {
    const auto it = std::find_if(
        processes.begin(), processes.end(),
        [current](const PROCESSENTRY32W& entry) {
          return entry.th32ProcessID == current;
        });
    if (it == processes.end()) {
      break;
    }

    if (_wcsicmp(it->szExeFile, L"chrome.exe") != 0) {
      break;
    }

    ancestor = it->th32ProcessID;
    current = it->th32ParentProcessID;
  }

  return ancestor;
}

DWORD NativeAudioPlugin::FindForegroundProcessIdByExecutableName(
    const std::wstring& executable_name) const {
  const HWND foreground_window = GetForegroundWindow();
  if (foreground_window == nullptr) {
    return 0;
  }

  DWORD process_id = 0;
  GetWindowThreadProcessId(foreground_window, &process_id);
  if (process_id == 0) {
    return 0;
  }

  return IsProcessExecutableName(process_id, executable_name) ? process_id : 0;
}

DWORD NativeAudioPlugin::FindRootProcessIdByExecutableName(
    const std::wstring& executable_name) const {
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return 0;
  }

  std::vector<PROCESSENTRY32W> matches;
  PROCESSENTRY32W process_entry = {};
  process_entry.dwSize = sizeof(process_entry);

  if (Process32FirstW(snapshot, &process_entry)) {
    do {
      if (_wcsicmp(process_entry.szExeFile, executable_name.c_str()) == 0) {
        matches.push_back(process_entry);
      }
    } while (Process32NextW(snapshot, &process_entry));
  }

  CloseHandle(snapshot);

  if (matches.empty()) {
    return 0;
  }

  for (const auto& entry : matches) {
    bool parent_is_same_executable = false;
    for (const auto& candidate : matches) {
      if (candidate.th32ProcessID == entry.th32ParentProcessID) {
        parent_is_same_executable = true;
        break;
      }
    }
    if (!parent_is_same_executable) {
      return entry.th32ProcessID;
    }
  }

  return matches.front().th32ProcessID;
}
