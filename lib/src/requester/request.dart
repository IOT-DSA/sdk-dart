part of dslink.requester;

/// request class handles raw response from responder
class DsRequest {
  final DsRequester requester;
  final int rid;
  /// raw request callback
  final _DsRequestUpdater updater;
  bool _isClosed = false;
  bool get isClosed => _isClosed;

  DsRequest(this.requester, this.rid, this.updater);

  String streamStatus = DsStreamStatus.initialize;

  void _update(Map m) {
    if (m['stream'] is String) {
      streamStatus = m['stream'];
    }
    List updates;
    List columns;
    if (m['updates'] is List) {
      updates = m['updates'];
    }
    if (m['columns'] is List) {
      columns = m['columns'];
    }
    // remove the request from global Map
    if (streamStatus == DsStreamStatus.closed) {
      requester._requests.remove(rid);
    }
    updater(streamStatus, updates, columns);
  }

  /// close the request from the client side
  void _close() {
    if (streamStatus != DsStreamStatus.closed) {
      streamStatus = DsStreamStatus.closed;
      updater(DsStreamStatus.closed, null, null);
    }
  }

  /// close the request from the client side
  void close() {
    // _close will also be called later from the requester;
    requester.closeRequest(this);
  }
}
