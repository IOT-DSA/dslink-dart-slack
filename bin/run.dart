import "package:dslink_slack/slack.dart";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(args, "Slack-", defaultNodes: {
    "Create_Connection": {
      r"$invokable": "write",
      r"$name": "Create Connection",
      r"$is": "createConnection",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "token",
          "type": "string"
        }
      ],
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        },
        {
          "name": "message",
          "type": "string"
        }
      ]
    }
  }, profiles: {
    "createConnection": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      var name = params["name"];
      var token = params["token"];

      if (name == null) {
        return {
          "success": false,
          "message": "name was not specified."
        };
      }

      if ((link.provider as SimpleNodeProvider).nodes.containsKey("/${name}")) {
        return {
          "success": false,
          "message": "connection with the specified name exists."
        };
      }

      if (token == null) {
        return {
          "success": false,
          "message": "token was not specified."
        };
      }

      link.addNode("/${name}", {
        r"$is": "connection",
        r"$$slack_token": token
      });

      link.save();

      return {
        "success": true,
        "message": "Success!"
      };
    }),
    "connection": (String path) => new ConnectionNode(path),
    "listAllMembers": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      var x = link["/${path.split("/")[1]}/Team_Members"];
      return x.children.values.map((SimpleNode x) {
        if (x.path.endsWith("/List_All")) {
          return null;
        }
        n(String nl) => link.val("${x.path}/${nl}");
        return {
          "id": n("ID"),
          "name": x.configs[r"$name"],
          "username": n("Username"),
          "realname": n("Real_Name"),
          "presence": n("Presence"),
          "image": n("Profile_Image")
        };
      }).where((a) => a != null).toList();
    }),
    "sendChannelMessage": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      var id = link.val(new Path(path).parentPath + "/ID");
      ConnectionNode conn = link[path.split("/").take(2).join("/")];
      conn.bot.sendMessage(id, params["message"]);
    })
  }, autoInitialize: false);

  link.configure();
  link.init();
  link.connect();
}

class ConnectionNode extends SimpleNode {
  ConnectionNode(String path) : super(path);

  SlackClient client;
  SlackBot bot;

  @override
  onCreated() {
    var token = get(r"$$slack_token");
    client = new SlackClient(token);
    doInit();
  }

  doInit() async {
    bot = await client.createBot();
    var info = await client.getTeamInfo();

    var x = {
      r"@icon": info.image34,
      "Team_Name": {
        r"$type": "string",
        r"$name": "Team Name",
        r"?value": info.name
      },
      "ID": {
        r"$type": "string",
        "?value": info.id
      },
      "Team_Members": {
        r"$name": "Team Members",
        "List_All": {
          r"$is": "listAllMembers",
          r"$invokable": "read",
          r"$name": "List All",
          r"$result": "table",
          r"$columns": [
            {
              "name": "id",
              "type": "string"
            },
            {
              "name": "name",
              "type": "string"
            },
            {
              "name": "username",
              "type": "string"
            },
            {
              "name": "realname",
              "type": "string"
            },
            {
              "name": "presence",
              "type": "string"
            },
            {
              "name": "image",
              "type": "string"
            }
          ]
        }
      },
      "Channels": {
        r"$name": "Channels"
      }
    };

    for (String key in x.keys) {
      if (key.startsWith(r"$")) {
        configs[key] = x[key];
        continue;
      } else if (key.startsWith(r"@")) {
        attributes[key] = x[key];
        continue;
      }

      try {
        link.removeNode("${path}/${key}");
      } catch (e) {}
      link.addNode("${path}/${key}", x[key]);
    }

    updateList(r"$is");

    bot.on("message").listen((e) {
      String user = e["user"];
      String channel = e["channel"];
      String text = e["text"];
      String id = e["ts"];

      var node = link["${path}/Channels/${channel}"];
      if (node == null) {
        return;
      }
      SimpleNode mn = node.getChild("Message");
      mn.updateValue(new ValueUpdate(text));
      SimpleNode idn = mn.getChild("ID");
      SimpleNode un = mn.getChild("User");
      idn.updateValue(id);
      un.updateValue(new ValueUpdate(user));
    });

    bot.on("user_change").listen((e) {
      syncUsers();
    });

    bot.on("presence_change").listen((e) {
      try {
        link.val("${path}/Team_Members/${e["user"]}/Presence", e["presence"]);
      } catch (e) {}
    });

    bot.on("manual_presence_change").listen((e) {
      try {
        link.val("${path}/Team_Members/${e["user"]}/Presence", e["presence"]);
      } catch (e) {}
    });

    bot.on("team_join").listen((e) {
      syncUsers();
    });

    bot.on("channel_created").listen((e) {
      syncChannels();
    });

    bot.on("channel_joined").listen((e) {
      syncChannels();
    });

    bot.on("channel_left").listen((e) {
      syncChannels();
    });

    bot.on("channel_deleted").listen((e) {
      syncChannels();
    });

    bot.on("channel_rename").listen((e) {
      syncChannels();
    });

    await syncUsers(initial: true);
    await syncChannels();
  }

  syncUsers({bool initial: false}) async {
    var users = await client.listTeamMembers();
    for (var x in (link.provider as SimpleNodeProvider).nodes.keys.toList()) {
      if (x.startsWith("${path}/Team_Members/") && !x.endsWith("/List_All")) {
        link.removeNode(x);
      }
    }

    for (SlackUser user in users) {
      await addTeamMember(user, initial: initial);
    }
  }

  syncChannels() async {
    var channels = await client.listChannels();
    link.removeNode("${path}/Channels");
    link.addNode("${path}/Channels", {});
    for (var channel in channels) {
      await addChannel(channel);
    }
  }

  addChannel(SlackChannel channel) async {
    var p = "${path}/Channels/${channel.id}";
    link.removeNode(p);
    try {
      channel = await client.getChannelInfo(channel.id);
    } catch (e) {}
    SlackChannelMessage msg = channel.latestMessage == null ?
      new SlackChannelMessage() :
      channel.latestMessage;
    var m = {
      r"$name": channel.name,
      "ID": {
        r"$type": "string",
        "?value": channel.id
      },
      "Name": {
        r"$type": "string",
        "?value": channel.name
      },
      "Is_Member": {
        r"$name": "Is Member",
        r"$type": "bool",
        "?value": channel.isMember
      },
      "Topic": {
        r"$type": "string",
        "?value": channel.topic.value,
        "Set_By": {
          r"$name": "Set By",
          r"$type": "string",
          "?value": channel.topic.creator
        },
        "Last_Set": {
          r"$name": "Last Set",
          r"$type": "number",
          "?value": channel.topic.lastSet
        }
      },
      "Purpose": {
        r"$type": "string",
        "?value": channel.purpose.value,
        "Set_By": {
          r"$name": "Set By",
          r"$type": "string",
          "?value": channel.purpose.creator
        },
        "Last_Set": {
          r"$name": "Last Set",
          r"$type": "number",
          "?value": channel.purpose.lastSet
        }
      },
      "Message": {
        r"$type": "string",
        "?value": msg.text,
        "User": {
          r"$type": "string",
          "?value": msg.user
        },
        "ID": {
          r"$type": "string",
          "?value": msg.ts
        }
      }
    };

    if (channel.isMember) {
      m.addAll({
        "Send_Message": {
          r"$name": "Send Message",
          r"$is": "sendChannelMessage",
          r"$invokable": "write",
          r"$params": [
            {
              "name": "message",
              "type": "string"
            }
          ]
        }
      });
    }

    link.addNode(p, m);
  }

  addTeamMember(SlackUser user, {bool initial: false}) async {
    if (user.deleted) {
      return;
    }

    var presence = (
        initial ?
          bot.initialState["users"].firstWhere((x) => x["id"] == user.id)["presence"] :
          await client.getUserPresence(user.id)
    );

    link.addNode("${path}/Team_Members/${user.id}", {
      r"$name": user.profile.realName != null && user.profile.realName.isNotEmpty ? user.profile.realName : user.name,
      r"@icon": user.profile.image32,
      "ID": {
        r"$type": "string",
        "?value": user.id
      },
      "Username": {
        r"$type": "string",
        "?value": user.name
      },
      "Real_Name": {
        r"$name": "Real Name",
        r"$type": "string",
        "?value": user.profile.realName
      },
      "Color": {
        r"$type": "string",
        "?value": user.color
      },
      "Presence": {
        r"$type": "string",
        "?value": presence
      },
      "Administrator": {
        r"$name": "Is Admin",
        r"$type": "bool",
        "?value": user.isAdmin == null ? false : user.isAdmin
      },
      "Owner": {
        r"$name": "Is Owner",
        r"$type": "bool",
        "?value": user.isOwner == null ? false : user.isOwner
      },
      "Profile_Image": {
        r"$name": "Profile Image",
        r"$type": "string",
        "?value": user.profile.image192
      }
    });
    link["${path}/Team_Members"].addChild(user.id, link["${path}/Team_Members/${user.id}"]);
    save();
  }

  @override
  Map save() {
    return {
      r"$is": "connection",
      r"$$slack_token": client.token
    };
  }
}
