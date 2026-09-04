import 'dart:io';
import '../../../core/utils/url_container.dart';
import '../../../core/utils/util.dart';
import '../../model/chat/message_model.dart';
import '../../model/global/response_model/response_model.dart';
import '../../services/api_service.dart';

class ChatRepo {
  static const Set<String> _documentExtensions = {'pdf', 'doc', 'docx'};

  static String resolveAttachmentKey(String filePath) {
    final lowerPath = filePath.toLowerCase();

    if (lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.gif') ||
        lowerPath.endsWith('.webp')) {
      return 'image';
    }

    if (lowerPath.endsWith('.mp4') || lowerPath.endsWith('.mov') || lowerPath.endsWith('.3gp')) {
      return 'video';
    }

    if (lowerPath.endsWith('.ogg') ||
        lowerPath.endsWith('.opus') ||
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.mp3') ||
        lowerPath.endsWith('.wav') ||
        lowerPath.endsWith('.aac') ||
        lowerPath.endsWith('.mpeg') ||
        lowerPath.endsWith('.amr') ||
        lowerPath.endsWith('.flac') ||
        lowerPath.endsWith('.wma') ||
        lowerPath.endsWith('.aiff') ||
        lowerPath.endsWith('.alac')) {
      return 'audio';
    }

    return 'document';
  }

  static bool isAllowedDocumentExtension(String filePath) {
    final segments = filePath.split('.');
    if (segments.length < 2) return false;
    final extension = segments.last.toLowerCase();
    return _documentExtensions.contains(extension);
  }

  static bool isValidMessageFile(File? file) {
    return file != null && file.existsSync() && file.lengthSync() > 0;
  }

  Future<ResponseModel> getChatsDataRepo(String conversationId, String page, String search) async {
    String url = '${UrlContainer.baseUrl}${UrlContainer.chatsDataEndPoint}$conversationId?page=$page&search=$search';

    ResponseModel responseModel = await ApiService.getRequest(url);

    return responseModel;
  }

  Future<ResponseModel> syncChatsDataRepo(String conversationId, String lastMessageId) async {
    String url = '${UrlContainer.baseUrl}${UrlContainer.chatsDataEndPoint}$conversationId?after_message_id=$lastMessageId';

    ResponseModel responseModel = await ApiService.getRequest(url);

    return responseModel;
  }

  Future<ResponseModel> seenMessageRepo(String conversationId) async {
    final url = '${UrlContainer.baseUrl}${UrlContainer.seenMessageUrl}/$conversationId';
    final responseModel = await ApiService.getRequest(url);

    return responseModel;
  }

  Future<ResponseModel> downloadFileRepo(String mediaId, String filePath) async {
    String url = '${UrlContainer.baseUrl}${UrlContainer.downloadMediaDataEndPoint}$mediaId';
    ResponseModel responseModel = await ApiService.downloadFile(url, filePath);

    return responseModel;
  }

  Future<ResponseModel> sendMessageRepo(MessageModel messageModel, String? chatId) async {
    final Map<String, dynamic> map = {};

    print("message map ---- $map");

    if (chatId == null) {
      map.addAll({
        'conversation_id': messageModel.chatId,
        'message': messageModel.message,
      });
      if (messageModel.id != null && messageModel.id!.isNotEmpty) {
        map['wa_message_id'] = messageModel.id;
      }
    } else {
      map.addAll({'message_id': chatId});
    }

    Map<String, File> attachmentFile = {};

    if (messageModel.file != null) {
      final file = messageModel.file!;
      if (!isValidMessageFile(file)) {
        return ResponseModel(
          isSuccess: false,
          message: 'The parameter file is required.',
          statusCode: 422,
          responseJson: {'error': 'The parameter file is required.'},
        );
      }

      final filePath = file.path;
      final key = resolveAttachmentKey(filePath);
      if (key == 'document' && !isAllowedDocumentExtension(filePath)) {
        return ResponseModel(
          isSuccess: false,
          message: 'The document must be a file of type: pdf, doc, docx.',
          statusCode: 422,
          responseJson: {'error': 'The document must be a file of type: pdf, doc, docx.'},
        );
      }

      attachmentFile = {key: file};
    }

    String url = '${UrlContainer.baseUrl}${chatId != null ? UrlContainer.resendMessageUrl : UrlContainer.sendMessageUrl}';
    print("message map ---- $map");
    final response = await ApiService.postMultiPartRequest(url, map, attachmentFile);
    printW(response.responseJson);
    return response;
  }
}
