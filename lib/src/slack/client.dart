part of slack.api;

class SlackClient {
  final String token;
  final http.Client client;

  SlackClient(this.token, {http.Client client}) :
    this.client = client == null ? new http.Client() : client;

  Future<Map<String, dynamic>> sendRequest(String method, {Map<String, dynamic> parameters}) {
    if (parameters == null) {
      parameters = {};
    }

    for (var key in parameters.keys.toList()) {
      parameters[key] = parameters[key].toString();
    }

    parameters["token"] = token;

    var qs = "";
    var i = 0;
    for (var key in parameters.keys) {
      if (i != 0) {
        qs += "&";
      }
      qs += "${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(parameters[key])}";
      i++;
    }

    var url = "https://slack.com/api/${method}?${qs}";

    print(url);

    return client.post(url, body: JSON.encode(parameters)).then((response) {
      if (response.statusCode != 200) {
        throw new Exception("ERROR: Response Status Code was ${response.statusCode}");
      }

      var json = JSON.decode(response.body);
      print(json);
      if (!json["ok"]) {
        throw new SlackError(json["error"]);
      }
      return json;
    });
  }

  Future<List<dynamic>> _createWebSocket() {
    return sendRequest("rtm.start").then((response) async {
      return [await WebSocket.connect(response["url"]), response];
    });
  }

  Future<SlackBot> createBot() {
    return _createWebSocket().then((stuff) {
      var socket = stuff[0];
      var state = stuff[1];
      return new SlackBot(state, socket);
    });
  }

  Future<List<SlackUser>> listTeamMembers() {
    return sendRequest("users.list").then((response) {
      return response["members"].map((it) {
        var user = SlackUser.fromJSON(it);
        _nameCache[user.id] = user.name;
        return user;
      }).toList();
    });
  }

  Future<SlackChannel> getChannelInfo(String id) {
    return sendRequest("channels.info", parameters: {
      "channel": id
    }).then((response) {
      return SlackChannel.fromJSON(response["channel"]);
    });
  }

  Future<SlackUser> getUserInfo(String id) {
    return sendRequest("users.info", parameters: {
      "user": id
    }).then((response) {
      var user = SlackUser.fromJSON(response["user"]);
      _nameCache[user.id] = user.name;
      return user;
    });
  }

  Future<String> getChannelName(String id) async {
    if (_nameCache.containsKey(id)) {
      return _nameCache[id];
    }

    return getChannelInfo(id).then((it) => _nameCache[id] = it["name"]);
  }

  Future<String> getUserName(String id) async {
    if (_nameCache.containsKey(id)) {
      return _nameCache[id];
    }

    return getUserInfo(id).then((it) => _nameCache[id] = it.name);
  }

  Future<bool> setChannelTopic(String id, String topic) {
    return sendRequest("channels.setTopic", parameters: {
      "channel": id,
      "topic": topic
    }).then((response) {
      return true;
    });
  }

  Future<String> lookupChannelId(String name) async {
    if (_nameCache.values.contains(name)) {
      return _nameCache.keys.firstWhere((x) => _nameCache[x] == name);
    }

    return listChannels().then((List<SlackChannel> channels) {
      var possible = channels.where((it) => it.name == name || it.name == name.substring(1));
      if (possible.isEmpty) {
        return null;
      }
      var real = possible.first;
      _nameCache[real.id] = real.name;
      return real.id;
    });
  }

  Future<SlackChannel> joinChannel(String name) {
    return sendRequest("channels.join", parameters: {
      "name": name
    }).then((data) {
      return SlackChannel.fromJSON(data["channel"]);
    });
  }

  Future<SlackTeamInfo> getTeamInfo() async {
    var json = await sendRequest("team.info");
    SlackTeamInfo info = SlackTeamInfo.fromJSON(json["team"]);
    return info;
  }

  Future<List<SlackChannelMessage>> getChannelHistory(String channel, {int count}) async {
    var request = {};
    request["channel"] = channel;
    if (count != null) {
      request["count"] = count;
    }
    var response = await sendRequest("channels.history", parameters: request);
    List<Map<String, dynamic>> msgs = response["messages"];

    return msgs.map(SlackChannelMessage.fromJSON).toList();
  }

  Future leaveChannel(String id) {
    return sendRequest("channels.leave", parameters: {
      "channel": id
    });
  }

  Future<bool> setChannelPurpose(String id, String purpose) {
    return sendRequest("channels.setTopic", parameters: {
      "channel": id,
      "purpose": purpose
    }).then((response) {
      return true;
    });
  }

  void resetNameCache() {
    _nameCache.clear();
  }

  Map<String, String> _nameCache = {};

  Future<String> getUserPresence(String id) async {
    return sendRequest("users.getPresence", parameters: {
      "user": id
    }).then((x) => x["presence"]);
  }

  Future<List<SlackChannel>> listChannels() async {
    var json = await sendRequest("channels.list");
    return json["channels"].map((x) => SlackChannel.fromJSON(x)).toList();
  }
}

class SlackUser {
  String id;
  String presence;
  String name;
  bool deleted;
  String color;
  SlackUserProfile profile;
  bool isAdmin;
  bool isOwner;
  bool has2fa;
  bool hasFiles;

  static SlackUser fromJSON(input) {
    var json = input is String ? JSON.decode(input) : input;
    var user = new SlackUser();
    user.id = json["id"];
    user.name = json["name"];
    user.deleted = json["deleted"];
    user.color = json["color"];
    user.profile = SlackUserProfile.fromJSON(json["profile"]);
    user.isAdmin = json["is_admin"];
    user.isOwner = json["is_owner"];
    user.has2fa = json["has_2fa"];
    user.hasFiles = json["has_files"];
    user.presence = json["presence"];
    return user;
  }
}

class SlackTeamInfo {
  String id;
  String name;
  String image34;
  String image44;
  String image68;
  String image88;
  String image102;
  String image132;
  bool isImageDefault;

  static SlackTeamInfo fromJSON(json) {
    if (json == null) {
      return null;
    }

    var id = json["id"];
    var name = json["name"];
    Map ic = json["icon"];
    var x = new SlackTeamInfo();
    x.id = id;
    x.name = name;
    x.image34 = ic["image_34"];
    x.image44 = ic["image_44"];
    x.image68 = ic["image_68"];
    x.image102 = ic["image_102"];
    x.image132 = ic["image_132"];
    x.isImageDefault = ic["image_default"];
    return x;
  }
}

class SlackUserProfile {
  String firstName;
  String lastName;
  String realName;
  String email;
  String skype;
  String phone;
  String image24;
  String image32;
  String image48;
  String image72;
  String image192;

  static SlackUserProfile fromJSON(input) {
    var json = input is String ? JSON.decode(input) : input;
    var profile = new SlackUserProfile();
    profile.firstName = json["first_name"];
    profile.lastName = json["last_name"];
    profile.realName = json["real_name"];
    profile.email = json["email"];
    profile.skype = json["skype"];
    profile.phone = json["phone"];
    profile.image24 = json["image_24"];
    profile.image32 = json["image_32"];
    profile.image48 = json["image_48"];
    profile.image72 = json["image_72"];
    profile.image192 = json["image_192"];
    return profile;
  }
}

class SlackChannel {
  String id;
  String name;
  int created;
  String creator;
  bool isArchived;
  bool isMember;
  int numberOfMembers;
  SlackChannelTopic topic;
  SlackChannelTopic purpose;
  SlackChannelMessage latestMessage;

  static SlackChannel fromJSON(json) {
    var x = new SlackChannel();
    x.id = json["id"];
    x.name = json["name"];
    x.created = json["created"];
    x.creator = json["creator"];
    x.isArchived = json["is_archived"];
    x.isMember = json["is_member"];
    x.numberOfMembers = json["num_members"];
    x.topic = SlackChannelTopic.fromJSON(json["topic"]);
    x.purpose = SlackChannelTopic.fromJSON(json["purpose"]);
    x.latestMessage = SlackChannelMessage.fromJSON(json["latest"], channel: x.id);
    return x;
  }
}

class SlackChannelMessage {
  String channel;
  String text;
  String ts;
  String user;

  static SlackChannelMessage fromJSON(json, {String channel}) {
    if (json == null) {
      return null;
    }
    var x = new SlackChannelMessage();
    x.channel = channel == null ? json["channel"] : channel;
    x.text = json["text"];
    x.user = json["user"];
    x.ts = json["ts"];
    return x;
  }
}

class SlackChannelTopic {
  String value;
  String creator;
  int lastSet;

  static SlackChannelTopic fromJSON(json) {
    var x = new SlackChannelTopic();
    x.value = json["value"];
    x.creator = json["creator"];
    x.lastSet = json["last_set"];
    return x;
  }
}
