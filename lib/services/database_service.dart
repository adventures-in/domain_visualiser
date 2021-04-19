import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain_visualiser/actions/profile/store_profile_data_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/extensions/actions_stream_controller_extensions.dart';
import 'package:domain_visualiser/extensions/firestore_extensions.dart';
import 'package:domain_visualiser/models/class_box.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class DatabaseService {
  /// The [FirebaseFirestore] instance
  final FirebaseFirestore _firestore;

  /// The stream of the [_storeController] is used just once on app load, to
  /// connect the [_storeController] to the redux [Store]
  /// Functions that observe parts of the database thus don't return anything,
  /// they just connect the store to the database and keep the subscription so
  /// functions that disregard (stop observing) that part of the database just
  /// cancel the subscription.
  Stream<ReduxAction> get storeStream => _eventsController.stream;

  /// Keep track of the subscriptions so we can cancel them later.
  Map<DatabaseSectionEnum, StreamSubscription> subscriptions = {};

  /// The [_storeController] is connected to the redux [Store] via [storeStrea]
  /// and is used by the [DatabaseService] to add actions to the stream where
  /// they will be dispatched by the store.
  final StreamController<ReduxAction> _eventsController;

  DatabaseService(
      {FirebaseFirestore? database,
      StreamController<ReduxAction>? eventsController})
      : _firestore = database ?? FirebaseFirestore.instance,
        _eventsController = eventsController ?? StreamController<ReduxAction>();

  /// Observe the document at /adventurers/${uid} and convert each
  /// [DocumentSnapshot] into a [ReduxAction] then send to the store using the
  /// passed in [StreamController].
  void connectProfileData({required String uid}) {
    final dbSection = DatabaseSectionEnum.profileData;

    try {
      // connect the database to the store and keep the subscription
      subscriptions[dbSection] =
          _firestore.doc('profiles/$uid').snapshots().listen((docSnapshot) {
        try {
          if (docSnapshot.exists) {
            _eventsController
                .add(StoreProfileDataAction(data: docSnapshot.toProfileData()));
          }
        } catch (error, trace) {
          _eventsController.addProblem(error, trace);
        }
      }, onError: _eventsController.addProblem);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  void disconnect(DatabaseSectionEnum dbSection) =>
      subscriptions[dbSection]?.cancel();

  // Future<void> createSection(
  //     {required String uid, required String name}) async {
  //   try {
  //     await _firestore.doc('new/$uid').set(<String, Object>{
  //       'section': {'name': name}
  //     });

  //     final dbSection = DatabaseSection.newEntries;
  //     subscriptions[dbSection] =
  //         _firestore.doc('new/$uid').snapshots().listen((doc) {
  //       try {
  //         if (!doc.exists) {
  //           _eventsController
  //               .add(UpdateSectionsVMAction(creatingNewSection: false));
  //           subscriptions[dbSection]?.cancel();
  //         }
  //       } catch (error, trace) {
  //         _eventsController.addProblem(error, trace);
  //         subscriptions[dbSection]?.cancel();
  //       }
  //     }, onError: _eventsController.addProblem, cancelOnError: true);
  //   } catch (error, trace) {
  //     _eventsController.addProblem(error, trace);
  //   }
  // }

  /// Observe the collection at /sections/ and convert each
  /// [CollectionSnapshot] into a [ReduxAction] then send to the store using the
  /// passed in [StreamController].
  void connectSections() {
    final dbSection = DatabaseSectionEnum.classBoxes;

    try {
      // connect the database to the store and keep the subscription
      subscriptions[dbSection] = _firestore
          .collection('class-boxes')
          .snapshots()
          .listen((collectionSnapshot) {
        try {
          final list = <ClassBox>[];
          for (final querySnapshot in collectionSnapshot.docs) {
            list.add(querySnapshot.toClassBox());
          }
          _eventsController.add(StoreClassBoxesAction(list: list.lock));
        } catch (error, trace) {
          _eventsController.addProblem(error, trace);
        }
      }, onError: _eventsController.addProblem);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }
}
