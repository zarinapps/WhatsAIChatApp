import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../../../core/utils/util.dart';
import '../../model/chat/chat_data_response_model.dart';
import '../../repo/chat/chat_repo.dart';
import '../../services/pusher_service.dart';
import '../../db/database_helper.dart';
import 'chat_controller.dart';

class PusherChatServiceController extends GetxController {
  final ChatRepo repo;
  late final ChatController controller;

  PusherChatServiceController({required this.repo});

  @override
  void onInit() {
    super.onInit();
    controller = Get.find();
    PusherManager().addListener(onEvent);
  }

  void onEvent(PusherEvent event) {
    try {
      if (event.eventName != 'receive-message') return;
      printX("ChatScrren onEvent: ${event.data}");
      var msgData = jsonDecode(event.data);
      bool isNewMsg = msgData["data"] != null && msgData["data"]["newMessage"]?.toString() == "true";
      MessagesData msg = MessagesData.fromJson(msgData["data"]["message"]);

      if (isNewMsg) {
        // Always insert incoming new messages into local DB
        DatabaseHelper.instance.insertMessage(msg);
        
        if (controller.conversationId == msg.conversationId) {
          final shouldShowNewMessage = controller.isNearLatestMessage;
          final wasInserted = controller.insertMessageIfAbsent(msg);
          if (!wasInserted) return;
          controller.update(['chat_screen_main']);

          WidgetsBinding.instance.ensureVisualUpdate();
          if (shouldShowNewMessage) {
            controller.scrollToLatestMessage();
          }
        }
      } else {
        // Status update
        if (msg.id != null) {
          DatabaseHelper.instance.updateMessageStatusById(msg.id!, msg.status ?? "");
        }
        
        if (controller.conversationId == msg.conversationId) {
          controller.messages.firstWhereOrNull((e) => e.id == msg.id)?.status = msg.status;
          controller.update();
        }
      }
    } catch (e) {
      printE("ChatService onEvent error: $e");
    }
  }

  @override
  void onClose() {
    PusherManager().removeListener(onEvent);
    super.onClose();
  }

  Future<void> ensureConnection(String channelName) async {
    await PusherManager().checkAndInitIfNeeded(channelName);
  }
}
