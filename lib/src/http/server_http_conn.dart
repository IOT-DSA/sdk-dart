part of dslink.http_server;

class HttpServerConnection implements ServerConnection {
  PassiveChannel _responderChannel;
  ConnectionChannel get responderChannel => _responderChannel;

  PassiveChannel _requesterChannel;
  ConnectionChannel get requesterChannel => _requesterChannel;

  Completer<ConnectionChannel> _onRequestReadyCompleter = new Completer<ConnectionChannel>();
  Future<ConnectionChannel> get onRequesterReady => _onRequestReadyCompleter.future;

  HttpServerConnection() {
    _responderChannel = new PassiveChannel(this);
    _requesterChannel = new PassiveChannel(this);
    _onRequestReadyCompleter.complete(new Future.value(_requesterChannel));
  }
  bool _pendingCheck = false;
  bool _pendingSend = false;
  void requireSend() {
    _pendingSend = true;
    if (!_pendingCheck) {
      _pendingCheck = true;
      DsTimer.callLaterOnce(_checkSend);
    }
  }

  void close() {

  }
  Map _serverCommand;
  void addServerCommand(String key, Object value) {
    if (_serverCommand == null) {
      _serverCommand = {};
    }
    _serverCommand[key] = value;
    if (key != 'salt') {
      requireSend();
    }
  }

  HttpRequest _cachedInput;
  /// handle http long polling
  void handleInput(HttpRequest input) {
    _cachedInput = input;
    input.fold([], foldList).then((List merged) {
      Map m;
      try {
        m = JSON.decode(UTF8.decode(merged));
      } catch (err) {
      }
      if (m != null) {
        paseInput(m);
      }
      _checkSend();
    });
  }
  /// handle http short polling
  void handleInputS(HttpRequest input, String saltS) {
    input.response.headers.contentType = new ContentType("application", "json", charset: "utf-8");
    input.response.write('{"saltS":"$saltS"}');
    input.fold([], foldList).then((List merged) {
      Map m;
      try {
        m = JSON.decode(UTF8.decode(merged));
      } catch (err) {
      }
      input.response.close();
      if (m != null) {
        paseInput(m);
      }
    });
  }
  void paseInput(Map m) {
    if (m['responses'] is List) {
      // send responses to requester channel
      _requesterChannel.onReceiveController.add(m['responses']);
    }
    if (m['requests'] is List) {
      // send requests to responder channel
      _responderChannel.onReceiveController.add(m['requests']);
    }
  }

  void _checkSend() {
    _pendingCheck = false;
    if (_pendingSend && _cachedInput != null) {
      _send();
      _cachedInput = null;
    }
  }
  void _send() {
    _pendingSend = false;
    bool needSend = false;
    Map m;
    if (_serverCommand != null) {
      m = _serverCommand;
      _serverCommand = null;
      needSend = true;
    } else {
      m = {};
    }
    if (_responderChannel.getData != null) {
      List rslt = _responderChannel.getData();
      if (rslt != null && rslt.length != 0) {
        m['responses'] = rslt;
        needSend = true;
      }
    }
    if (_requesterChannel.getData != null) {
      List rslt = _requesterChannel.getData();
      if (rslt != null && rslt.length != 0) {
        m['requests'] = rslt;
        needSend = true;
      }
    }
    if (needSend) {
      print('http send: $m');
      _cachedInput.response.headers.contentType = new ContentType("application", "json", charset: "utf-8");
      _cachedInput.response.write(JSON.encode(m));
      _cachedInput.response.close();
    }
  }
}