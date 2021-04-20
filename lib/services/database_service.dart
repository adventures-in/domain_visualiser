import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain_visualiser/actions/domain-objects/store_class_boxes_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/extensions/firebase/firestore_extensions.dart';
import 'package:domain_visualiser/extensions/redux/actions_stream_controller_extensions.dart';
import 'package:domain_visualiser/models/domain-objects/class_box.dart';
import 'package:domain_visualiser/models/shared/database_section.dart';
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

  /// The [_eventsController] is connected to the redux [Store] via [storeStream]
  /// and is used by the [DatabaseService] to add actions to the stream where
  /// they will be dispatched by the store.
  final StreamController<ReduxAction> _eventsController;

  DatabaseService(
      {FirebaseFirestore? database,
      StreamController<ReduxAction>? eventsController})
      : _firestore = database ?? FirebaseFirestore.instance,
        _eventsController = eventsController ?? StreamController<ReduxAction>();

  /// Observe a collection at [section.location] and convert the resultant
  /// [DocumentSnapshot] into a [ReduxAction] to send to the store.
  void connect(DatabaseSection section) {
    try {
      // connect the database to the store and keep the subscription
      subscriptions[section.id] =
          _firestore.doc(section.location).snapshots().listen((snapshot) {
        try {
          if (snapshot.exists) {
            _eventsController.add(snapshot.toStoreAction(section.id));
          }
        } catch (error, trace) {
          _eventsController.addProblem(error, trace);
        }
      }, onError: _eventsController.addProblem);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  void disconnect(DatabaseSection section) =>
      subscriptions[section.id]?.cancel();

  Future<void> saveClassBox(ClassBox box) async {
    try {
      await _firestore.doc('domain-objects/${box.id}').set(box.toJson());
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

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
          _eventsController.add(StoreClassBoxesAction(list.lock));
        } catch (error, trace) {
          _eventsController.addProblem(error, trace);
        }
      }, onError: _eventsController.addProblem);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }
}
