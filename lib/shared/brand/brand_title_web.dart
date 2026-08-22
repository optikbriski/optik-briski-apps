// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void setWebDocumentTitle(String title) {
  html.document.title = title;
  html.document
      .querySelector('meta[name="apple-mobile-web-app-title"]')
      ?.setAttribute('content', title);
}
