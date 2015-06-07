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
    "connection": (String path) => new ConnectionNode(path)
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
        r"$name": "Team Members"
      }
    };

    for (var key in x.keys) {
      link.removeNode("${path}/${key}");
      link.addNode("${path}/${key}", x[key]);
    }

    bot.on("presence_change").listen((e) {
      link.val("/Team_Members/${e["user"]}/Presence", e["presence"]);
    });

    bot.on("manual_presence_change").listen((e) {
      link.val("/Team_Members/${e["user"]}/Presence", e["presence"]);
    });

    bot.on("team_join").listen((e) {
      syncUsers();
    });

    await syncUsers(initial: true);
  }

  syncUsers({bool initial: false}) async {
    var users = await client.listTeamMembers();
    for (SlackUser user in users) {
      await addTeamMember(user, initial: initial);
    }
  }

  addTeamMember(SlackUser user, {bool initial: false}) async {
    var presence = (
        initial ?
          bot.initialState["users"].firstWhere((x) => x["id"] == user.id)["presence"] :
          await client.getUserPresence(user.id)
    );
    link.addNode("${path}/Team_Members/${user.id}", {
      r"$name": user.profile.realName != null && user.profile.realName.isNotEmpty ? user.profile.realName : user.name,
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
      }
    });
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
