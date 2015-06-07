part of slack.api;

class SlackBot {
  final WebSocket socket;
  final Map<String, dynamic> initialState;

  Function receiveCallback;

  int _currentId = 0;

  SlackBot(this.initialState, this.socket) {
    _initialize();
  }

  void _initialize() {
    socket.listen((data) {
      var json = JSON.decode(data);

      var type = json["type"];

      if (_controllers.containsKey(type)) {
        _controllers[type].add(json);
      }

      if (receiveCallback != null) {
        receiveCallback(json);
      }
    });

    new Timer.periodic(new Duration(seconds: 5), (timer) {
      send("ping", {});
    });
  }

  void send(String type, Map data) {
    data["type"] = type;
    if (!data.containsKey("id")) {
      data["id"] = _currentId++;
    }
    socket.add(JSON.encode(data));
  }

  Stream<Map<String, dynamic>> on(String type) {
    if (!_controllers.containsKey(type)) {
      _controllers[type] = new StreamController<Map<String, dynamic>>.broadcast();
    }
    return _controllers[type].stream;
  }

  Map<String, StreamController<Map<String, dynamic>>> _controllers = {};

  void sendMessage(String target, String message, {bool user: false, int replyTo}) {
    var id = replyTo;

    if (id == null) {
      _currentId++;
      id = _currentId;
    }

    var map = {
      "id": id,
      "text": message,
      "parse": "full"
    };

    if (user) {
      map["user"] = target;
    } else {
      map["channel"] = target;
    }

    send("message", map);
  }
}
