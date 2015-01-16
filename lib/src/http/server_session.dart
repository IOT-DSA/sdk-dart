part of dslink.http_server;

/// a server session for both http and ws
class DsHttpServerSession implements ServerSession {
  final String dsId;

  Completer<DsRequester> _onRequesterReadyCompleter = new Completer<DsRequester>();
  Future<DsRequester> get onRequesterReady => _onRequesterReadyCompleter.future;

  final DsRequester requester;
  final Responder responder;
  final DsPublicKey publicKey;

  /// nonce for authentication, don't overwrite existing nonce
  DsSecretNonce _tempNonce;
  /// nonce after user verified the public key
  DsSecretNonce _verifiedNonce;

  DsSecretNonce get nonce => _verifiedNonce;

  ServerConnection _connection;

  /// 2 salts, salt saltS
  final List<int> salts = new List<int>(2);

  DsHttpServerSession(this.dsId, BigInteger modulus, {NodeProvider nodeProvider})
      : publicKey = new DsPublicKey(modulus),
        requester = new DsRequester(),
        responder = (nodeProvider != null) ? new Responder(nodeProvider) : null {
    for (int i = 0; i < 2; ++i) {
      salts[i] = DsaRandom.instance.nextUint8();
    }
  }
  /// check if public key matchs the dsId
  bool get valid {
    return publicKey.verifyDsId(dsId);
  }

  void initSession(HttpRequest request) {
    _tempNonce = new DsSecretNonce.generate();
//          isRequester: m['isResponder'] == true, // if client is responder, then server is requester
//          isResponder: m['isRequester'] == true // if client is requester, then server is responder

    // TODO, dont use hard coded id and public key
    request.response.write(JSON.encode({
      "id": "broker-dsa-5PjTP4kGLqxAAykKBU1MDUb0diZNOUpk_Au8MWxtCYa2YE_hOFaC8eAO6zz6FC0e",
      "publicKey": "AIHYvVkY5M_uMsRI4XmTH6nkngf2lMLXOOX4rfhliEYhv4Hw1wlb_I39Q5cw6a9zHSvonI8ZuG73HWLGKVlDmHGbYHWsWsXgrAouWt5H3AMGZl3hPoftvs0rktVsq0L_pz2Cp1h_7XGot87cLah5IV-AJ5bKBBFkXHOqOsIiDXNFhHjSI_emuRh01LmaN9_aBwfkyNq73zP8kY-hpb5mEG-sIcLvMecxsVS-guMFRCk_V77AzVCwOU52dmpfT5oNwiWhLf2n9A5GVyFxxzhKRc8NrfSdTFzKn0LvDPM29UDfzGOyWpfJCwrYisrftC3QbBD7e0liGbMCN5UgZsSssOk=",
      "wsUri": "/ws",
      "httpUri": "/http",
      "encryptedNonce": publicKey.encryptNonce(_tempNonce),
      "salt": '0x${salts[0]}',
      "saltS": '1x${salts[1]}',
      "min-update-interval-ms": 200
    }));
    request.response.close();
  }

  bool _verifySalt(int type, String hash) {
    if (hash == null) {
      return false;
    }
    if (_verifiedNonce != null && _verifiedNonce.verifySalt('${type}x${salts[type]}', hash)) {
      salts[type] += DsaRandom.instance.nextUint8() + 1;
      return true;
    } else if (_tempNonce != null && _tempNonce.verifySalt('${type}x${salts[type]}', hash)) {
      salts[type] += DsaRandom.instance.nextUint8() + 1;
      _nonceChanged();
      return true;
    }
    return false;
  }
  void _nonceChanged() {
    _verifiedNonce = _tempNonce;
    _tempNonce = null;
    if (_connection != null) {
      _connection.close();
      _connection = null;
    }
  }
  void _handleHttpUpdate(HttpRequest request) {
    if (!_verifySalt(0, request.uri.queryParameters['auth'])) {
      if (_connection is HttpServerConnection && _verifySalt(1, request.uri.queryParameters['authS'])) {
        // handle http short polling
        (_connection as HttpServerConnection).handleInputS(request, '1x${salts[1]}');
      } else {
        throw HttpStatus.UNAUTHORIZED;
      }
    }
    if (requester == null) {
      throw HttpStatus.FORBIDDEN;
    }
    if (_connection != null && _connection is! HttpServerConnection) {
      _connection.close();
      _connection = null;
    }
    if (_connection == null) {
      _connection = new HttpServerConnection();
      if (responder != null) {
        responder.connection = _connection.responderChannel;
      }
      if (requester != null) {
        requester.connection = _connection.requesterChannel;
        if (!_onRequesterReadyCompleter.isCompleted) {
          _onRequesterReadyCompleter.complete(requester);
        }
      }
    }
    _connection.addServerCommand('salt', '0x${salts[0]}');
    (_connection as HttpServerConnection).handleInput(request);
  }

  void _handleWsUpdate(HttpRequest request) {
    if (!_verifySalt(0, request.uri.queryParameters['auth'])) {
      throw HttpStatus.UNAUTHORIZED;
    }
    if (_connection != null) {
      _connection.close();
    }
    WebSocketTransformer.upgrade(request).then((WebSocket websocket) {
      _connection = new WebSocketConnection(websocket);
      _connection.addServerCommand('salt', '0x${salts[0]}');
      if (responder != null) {
        responder.connection = _connection.responderChannel;
      }
      if (requester != null) {
        requester.connection = _connection.requesterChannel;
        if (!_onRequesterReadyCompleter.isCompleted) {
          _onRequesterReadyCompleter.complete(requester);
        }
      }
    });
  }
}