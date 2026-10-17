import 'package:flutter/material.dart';

// Only full pages cover the map. Permission/consent dialogs must not cancel the
// location operation they are resolving.
final awaazRouteObserver = RouteObserver<PageRoute<dynamic>>();
