library dslink.http.websocket;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import '../../common.dart';
import '../../utils.dart';

class DsWebSocketConnection implements DsConnection {
  DsWebsocketChannel _responderChannel;
  DsConnectionChannel get responderChannel => _responderChannel;

  DsWebsocketChannel _requesterChannel;
  DsConnectionChannel get requesterChannel => _requesterChannel;

  Completer<DsConnectionChannel> _onRequestReadyCompleter = new Completer<DsConnectionChannel>();
  Future<DsConnectionChannel> get onRequesterReady => _onRequestReadyCompleter.future;

  final WebSocket socket;
  DsWebSocketConnection(this.socket) {
    _responderChannel = new DsWebsocketChannel(this);
    _requesterChannel = new DsWebsocketChannel(this);
    socket.listen(_onData, onDone: _onDone);
    // TODO, wait for the server to send {allowed} before complete this
    _onRequestReadyCompleter.complete(new Future.value(_requesterChannel));
  }

  void _onData(dynamic data) {
    print('onData: $data');
    if (data is String) {
      Map m;
      try {
        m = JSON.decode(data);
      } catch (err) {
        return;
      }
      if (m['responses'] is List) {
        // send responses to requester channel
        _requesterChannel._onReceiveController.add(m['responses']);
      }
      if (m['requests'] is List) {
        // send requests to responder channel
        _responderChannel._onReceiveController.add(m['requests']);
      }

    }
  }
  void _send() {
    Map m = {};
    bool needSend = false;
    if (_responderChannel._getData != null) {
      List rslt = _responderChannel._getData();
      if (rslt != null && rslt.length != 0) {
        m['responses'] = rslt;
        needSend = true;
      }
    }
    if (_requesterChannel._getData != null) {
      List rslt = _requesterChannel._getData();
      if (rslt != null && rslt.length != 0) {
        m['requests'] = rslt;
        needSend = true;
      }
    }
    if (needSend) {
      print('send: $m');
      socket.add(JSON.encode(m));
    }

  }
  void _onDone() {
    _responderChannel._onReceiveController.close();
    _responderChannel._onDisconnectController.complete(_requesterChannel);
    _requesterChannel._onReceiveController.close();
    _requesterChannel._onDisconnectController.complete(_requesterChannel);
  }

  void close() {
    socket.close();
    _onDone();
  }

}

class DsWebsocketChannel implements DsConnectionChannel {
  StreamController<List> _onReceiveController = new StreamController<List>();
  Stream<List> get onReceive => _onReceiveController.stream;

  List<Function> _processors = [];

  final DsWebSocketConnection conn;
  DsWebsocketChannel(this.conn) {
  }
  Function _getData;
  void sendWhenReady(List getData()) {
    _getData = getData;
    DsTimer.callLaterOnce(conn._send);
  }

  bool _isReady = false;
  bool get isReady => _isReady;
  void set isReady(bool val) {
    _isReady = val;
  }

  Completer<DsConnectionChannel> _onDisconnectController = new Completer<DsConnectionChannel>();
  Future<DsConnectionChannel> get onDisconnected => _onDisconnectController.future;

}
