import 'dart:math';

import 'package:call_app/app_navigator.dart';
import 'package:call_app/features/call/presentation/pages/join_screen.dart';
import 'package:call_app/firebase_options.dart';
import 'package:call_app/utils/notification/notification_utils.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final String selfCallerID = Random()
      .nextInt(999999)
      .toString()
      .padLeft(6, '0');

  @override
  void initState() {
    super.initState();
    NotificationUtils.initialize(
      userId: selfCallerID,
      navigatorKey: appNavigatorKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Call App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: JoinScreen(selfCallerId: selfCallerID),
    );
  }
}
