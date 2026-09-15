import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../data/orders_repository.dart';
import 'order_document.dart';
import 'order_document_pdf.dart';

/// What a finished download produced.
class OrderDocumentResult {
  const OrderDocumentResult({
    required this.kind,
    required this.fileName,
    required this.location,
  });

  final OrderDocumentKind kind;
  final String fileName;

  /// Where the file went, as the platform reported it.
  final String location;
}

/// Fetches an order, turns it into its invoice or receipt, and saves the PDF.
abstract final class OrderDocuments {
  /// Returns null when the shopper backed out of the save dialog.
  ///
  /// The order is read from the server here, at the moment of the download,
  /// through the signed-in session -- not taken from what the screen last
  /// cached. `GET /orders/{id}` answers only for the shopper's own orders, so
  /// that is also what keeps one customer out of another's paperwork; and a
  /// status that changed since the page was drawn still produces the right
  /// document.
  ///
  /// Throws [OrderDocumentUnavailable] when the order has nothing to print,
  /// and the server's [ApiError] when it could not be read.
  static Future<OrderDocumentResult?> download(
    String orderId, {
    String? accountEmail,
  }) async {
    final order = await OrdersRepository.instance.byId(orderId);
    final document = OrderDocument.fromOrder(order, accountEmail: accountEmail);
    if (document.lines.isEmpty) {
      throw OrderDocumentUnavailable(
        'This order has no items on record yet, so there is nothing to put '
        'on a ${document.kind.label.toLowerCase()}.',
      );
    }

    final bytes = await renderOrderDocument(document);
    final location = await OrderDocumentSaver.save(document.fileName, bytes);
    if (location == null) return null;

    return OrderDocumentResult(
      kind: document.kind,
      fileName: document.fileName,
      location: location,
    );
  }
}

/// Puts a finished PDF where the shopper chooses.
abstract final class OrderDocumentSaver {
  /// Replaces the platform dialog in tests.
  @visibleForTesting
  static Future<String?> Function(String fileName, Uint8List bytes)?
  saveOverride;

  /// Opens the system's own Save dialog, already named, and writes the file.
  ///
  /// The platform's dialog rather than a folder picked by the app: on Android
  /// it is the only way to put a file in Downloads -- or Drive, or anywhere
  /// else the shopper keeps things -- without asking for storage permission,
  /// and it is the dialog every desktop user already knows. Returns where the
  /// file went, or null if the dialog was dismissed.
  static Future<String?> save(String fileName, Uint8List bytes) async {
    final override = saveOverride;
    if (override != null) return override(fileName, bytes);

    final location = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    if (location == null) return null;

    // On Android, iOS and the web the plugin writes the bytes itself. On a
    // desktop it only asks where, and the writing is left to the caller.
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      await File(location).writeAsBytes(bytes, flush: true);
    }
    return location;
  }
}
