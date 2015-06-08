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
          "presence": n("Presence")
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
  onCreated() async {
    var token = get(r"$$slack_token");
    client = new SlackClient(token);
    bot = await client.createBot();

    var x = {
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
            }
          ]
        }
      },
      "Channels": {
        r"$name": "Channels"
      }
    };

    for (var key in x.keys) {
      link.removeNode("${path}/${key}");
      link.addNode("${path}/${key}", x[key]);
    }

    bot.on("presence_change").listen((e) {
      link.val("${path}/Team_Members/${e["user"]}/Presence", e["presence"]);
    });

    bot.on("manual_presence_change").listen((e) {
      link.val("${path}/Team_Members/${e["user"]}/Presence", e["presence"]);
    });

    bot.on("team_join").listen((e) {
      syncUsers();
    });

    await syncUsers(initial: true);
    await syncChannels();
  }

  syncUsers({bool initial: false}) async {
    var users = await client.listTeamMembers();
    for (var x in (link.provider as SimpleNodeProvider).nodes.keys) {
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
    for (var channel in channels) {
      await addChannel(channel);
    }
  }

  addChannel(SlackChannel channel) async {
    link.addNode("${path}/Channels/${channel.id}", {
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
        "?value": channel.topic.value
      },
      "Purpose": {
        r"$type": "string",
        "?value": channel.purpose.value
      },
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
