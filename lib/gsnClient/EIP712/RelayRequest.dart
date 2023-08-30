import 'ForwardRequest.dart';
import 'RelayData.dart';

class RelayRequest {
  ForwardRequest request;
  RelayData relayData;

  RelayRequest({required this.request, required this.relayData});
  List<dynamic> toJson() {
    return
    [  request.toJson(),
      relayData.toJson()];
  }
}
