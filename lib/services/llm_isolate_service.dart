import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:llama_cpp_dart/src/llama_cpp.dart';

class LLMIsolateService {
  // Singleton
  static final LLMIsolateService _instance = LLMIsolateService._internal();
  factory LLMIsolateService() => _instance;
  LLMIsolateService._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Completer<void> _initCompleter = Completer();
  
  // Request Management
  final Map<int, StreamController<String>> _pendingRequests = {};
  final Map<int, Completer<void>> _pendingResets = {}; // Track reset completers
  int _nextRequestId = 0;
  bool _isDisposed = false;

  bool get isReady => _initCompleter.isCompleted && !_isDisposed;

  Future<void> initialize(String modelPath) async {
    if (_isolate != null) return;

    print("[LLMIsolate] Spawning Isolate...");
    _isolate = await Isolate.spawn(_isolateEntry, _receivePort.sendPort);

    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        // Send Load Command immediately
        _sendPort!.send({
          'command': 'load',
          'modelPath': modelPath,
        });
      } else if (message is Map) {
        final type = message['type'];
        
        if (type == 'loaded') {
          print("[LLMIsolate] Model Loaded & Ready.");
          if (!_initCompleter.isCompleted) {
            _initCompleter.complete();
          }
        } else if (type == 'reset_done') {
          // Handle reset completion
          final id = message['id'] as int;
          if (_pendingResets.containsKey(id)) {
            _pendingResets[id]?.complete();
            _pendingResets.remove(id);
          }
        } else if (type == 'token') {
          final id = message['id'] as int;
          final token = message['data'] as String;
          _pendingRequests[id]?.add(token);
        } else if (type == 'done') {
          final id = message['id'] as int;
          _pendingRequests[id]?.close();
          _pendingRequests.remove(id);
        } else if (type == 'error') {
           final id = message['id'] as int;
           _pendingRequests[id]?.addError(message['error']);
           _pendingRequests[id]?.close();
           _pendingRequests.remove(id);
        }
      }
    });
  }

  /// Reset context before new generation (critical for preventing accumulation)
  Future<void> resetContext() async {
    if (!isReady) return;
    
    final completer = Completer<void>();
    final id = _nextRequestId++;
    
    // Register completer to be resolved by the main listener
    _pendingResets[id] = completer;
    
    _sendPort!.send({
      'command': 'reset',
      'id': id,
    });
    
    // Wait for reset or timeout
    try {
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          print("[LLMIsolate] ⚠️ Context reset timeout");
        },
      );
    } finally {
      _pendingResets.remove(id);
    }
  }

  Stream<String> generateStream(String prompt) async* {
    await _initCompleter.future;
    
    final id = _nextRequestId++;
    final controller = StreamController<String>();
    _pendingRequests[id] = controller;
    
    _sendPort!.send({
      'command': 'generate',
      'id': id,
      'prompt': prompt,
    });
    
    yield* controller.stream;
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    
    // Close all pending requests
    for (final controller in _pendingRequests.values) {
      await controller.close();
    }
    _pendingRequests.clear();
    
    // Kill isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    
    print("[LLMIsolate] Disposed successfully.");
  }
}

// -----------------------------------------------------------------------------
// ISOLATE ENTRY POINT
// -----------------------------------------------------------------------------
void _isolateEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort); // Handshake

  // Persistent Model State
  Llama? llama;
  Pointer<Char>? buf = malloc<Char>(256); // Reusable buffer

  receivePort.listen((message) async {
    if (message is Map) {
      final command = message['command'];

      if (command == 'load') {
        final modelPath = message['modelPath'];
        try {
          print("[LLMIsolate] Loading Model from: $modelPath");
          
          final contextParams = ContextParams()
            ..nCtx = 2048 
            ..nBatch = 1024
            ..nThreads = 4
            ..nPredict = 512;

          final modelParams = ModelParams()
            ..nGpuLayers = 0;

          final samplerParams = SamplerParams()
            ..greedy = true
            ..temp = 0.0
            ..topK = 40
            ..penaltyRepeat = 1.1 
            ..penaltyLastTokens = 64;

          llama = Llama(modelPath, modelParams, contextParams, samplerParams);
          print("[LLMIsolate] Model Loaded Successfully.");
          
          mainSendPort.send({'type': 'loaded'});
        } catch (e) {
          print("[LLMIsolate] Failed to load model: $e");
          mainSendPort.send({'type': 'error', 'id': -1, 'error': "Model Load Failed: $e"});
        }
      }
      else if (command == 'reset') {
        // 🔥 CRITICAL: Clear context/KV cache
        final id = message['id'];
        try {
          if (llama != null) {
            // Force clear by resetting the internal state
            // This is critical to prevent context accumulation
            llama!.clear();
            print("[LLMIsolate] ✅ Context/KV Cache cleared for request $id");
          }
          mainSendPort.send({'type': 'reset_done', 'id': id});
        } catch (e) {
          print("[LLMIsolate] ⚠️ Failed to reset context: $e");
          mainSendPort.send({'type': 'reset_done', 'id': id}); // Send anyway to unblock
        }
      } 
      else if (command == 'generate') {
        final id = message['id'];
        final prompt = message['prompt'];

        if (llama == null) {
          mainSendPort.send({'type': 'error', 'id': id, 'error': "Model not loaded"});
          return;
        }

        try {
           // 🔥 Set new prompt (this should start fresh generation)
           llama!.setPrompt(prompt);

           int tokenCount = 0;
           List<int> byteBuffer = [];
           bool hasOutput = false; // Track if we got any output
           
           while (true) {
             if (tokenCount >= 512) break;
             
             var (text, done) = llama!.getNext();
             if (done) break;

             // Raw Byte Recovery Logic
             final tokenId = llama!.batch.token.value;
             int n = Llama.lib.llama_token_to_piece(
               llama!.vocab, 
               tokenId, 
               buf!, 
               256, 
               0, 
               true
             );
             
             if (n >= 0) {
               final bytes = buf.cast<Uint8>().asTypedList(n);
               byteBuffer.addAll(bytes);
               
               try {
                 final decodedString = utf8.decode(byteBuffer, allowMalformed: false);
                 if (decodedString.isNotEmpty) {
                   mainSendPort.send({'type': 'token', 'id': id, 'data': decodedString});
                   byteBuffer.clear();
                   hasOutput = true;
                 }
               } catch (_) {
                 // Wait for more bytes
               }
             }

             tokenCount++;
           }
           
           // Flush remaining bytes
           if (byteBuffer.isNotEmpty) {
              try {
                final remaining = utf8.decode(byteBuffer, allowMalformed: true);
                if (remaining.isNotEmpty) {
                  mainSendPort.send({'type': 'token', 'id': id, 'data': remaining});
                  hasOutput = true;
                }
              } catch (_) {}
           }
           
           // 🔥 Log if no output was generated (helps debugging)
           if (!hasOutput) {
             print("[LLMIsolate] ⚠️ Warning: Generation completed but no tokens were produced!");
           }
           
           mainSendPort.send({'type': 'done', 'id': id});

        } catch (e) {
          mainSendPort.send({'type': 'error', 'id': id, 'error': e.toString()});
        }
      }
    }
  });
}
