import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:domain_visualiser/widgets/app-init/initial_page.dart';
import 'package:domain_visualiser/widgets/profile/profile_page.dart';
import 'package:domain_visualiser/widgets/shared/problem_page.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';

/// We are using extensions in order to keep models as PODOs and avoid other
/// dependencies in the app state.
extension NavigatorEntriesExt on IList<PageData> {
  /// Creates a list of [MaterialPage]s from [PagesData] used as the history
  /// for [Navigator]
  List<MaterialPage> toPages() {
    final materialPages = <MaterialPage>[];

    for (final pageData in this) {
      if (pageData is InitialPageData) {
        materialPages.add(MaterialPage<InitialPage>(
          key: ValueKey(InitialPage),
          child: InitialPage(),
        ));
      } else if (pageData is ProfilePageData) {
        materialPages.add(MaterialPage<ProfilePage>(
          key: ValueKey(ProfilePage),
          child: ProfilePage(),
        ));
      } else if ((pageData is ProblemPageData)) {
        materialPages.add(MaterialPage<ProblemPage>(
          key: ValueKey(ProblemPage),
          child: ProblemPage(pageData.problem),
        ));
      }
    }

    return materialPages;
  }
}
