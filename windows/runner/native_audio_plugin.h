#ifndef RUNNER_NATIVE_AUDIO_PLUGIN_H_
#define RUNNER_NATIVE_AUDIO_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <atomic>
#include <functional>
#include <memory>
#include <queue>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class WasapiLoopbackCapture {
 public:
  using AudioCallback = std::function<void(const std::vector<uint8_t>&)>;
  enum class CaptureMode {
    kSystemLoopback,
    kProcessLoopback,
  };

  WasapiLoopbackCapture();
  ~WasapiLoopbackCapture();

  bool Start(AudioCallback callback,
             CaptureMode mode,
             DWORD target_process_id,
             std::string* error_message);
  void Stop();
  bool is_recording() const { return is_recording_; }

 private:
  void CaptureLoop();
  bool ProcessAudioBuffer(const uint8_t* data, size_t frame_count, bool silent);
  float ReadSampleAsFloat(const uint8_t* frame_data, uint16_t channel_index) const;
  void AppendMonoSample(float sample);
  void FlushPendingChunks();
  void ResetResamplerState();

  AudioCallback callback_;
  std::thread capture_thread_;
  std::atomic<bool> is_recording_{false};
  std::atomic<bool> stop_requested_{false};
  CaptureMode capture_mode_ = CaptureMode::kSystemLoopback;
  DWORD target_process_id_ = 0;

  uint16_t channel_count_ = 0;
  uint16_t bits_per_sample_ = 0;
  uint16_t block_align_ = 0;
  uint32_t input_sample_rate_ = 0;
  bool input_is_float_ = false;

  std::vector<float> mono_resample_buffer_;
  double resample_cursor_ = 0.0;
  std::vector<uint8_t> pending_pcm_bytes_;
};

class NativeAudioPlugin {
 public:
  explicit NativeAudioPlugin(flutter::FlutterEngine* engine);
  ~NativeAudioPlugin();

  NativeAudioPlugin(const NativeAudioPlugin&) = delete;
  NativeAudioPlugin& operator=(const NativeAudioPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SendAudioChunk(const std::vector<uint8_t>& bytes);
  void DispatchPendingAudioChunks();
  bool CreateMessageWindow();
  void DestroyMessageWindow();
  static LRESULT CALLBACK MessageWindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam);
  bool IsProcessExecutableName(DWORD process_id,
                               const std::wstring& executable_name) const;
  DWORD FindChromeAncestorProcessId(DWORD process_id) const;
  DWORD FindForegroundProcessIdByExecutableName(
      const std::wstring& executable_name) const;
  DWORD FindRootProcessIdByExecutableName(const std::wstring& executable_name) const;

  WasapiLoopbackCapture capture_;
  WasapiLoopbackCapture::CaptureMode capture_mode_ =
      WasapiLoopbackCapture::CaptureMode::kSystemLoopback;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> control_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> pcm_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::mutex event_sink_mutex_;
  std::queue<std::vector<uint8_t>> pending_audio_chunks_;
  std::mutex pending_audio_mutex_;
  HWND message_window_ = nullptr;
};

#endif  // RUNNER_NATIVE_AUDIO_PLUGIN_H_
