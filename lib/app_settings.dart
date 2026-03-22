import 'package:flutter/material.dart';

final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier<Locale?>(null);

void setAppLocale(Locale? locale) {
  appLocaleNotifier.value = locale;
}
