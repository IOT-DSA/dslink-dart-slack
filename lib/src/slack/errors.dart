part of slack.api;

class SlackError {
  final String type;
  
  SlackError(this.type);
  
  @override
  String toString() => "SlackError(${type})";
}
