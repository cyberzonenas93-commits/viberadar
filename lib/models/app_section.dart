enum AppSection {
  // DISCOVER
  forYou,
  home,
  trending,
  search,
  artists,
  regions,
  genres,
  playlists,

  // COMMUNITY
  community,
  myProfile,
  upload,
  discoverDJs,

  // BUILD
  greatestOf,
  setBuilder,
  aiCopilot,

  // LIBRARY
  library,
  duplicates,
  savedCrates,
  watchlist,

  // EXPORT
  exports,

  // OTHER
  settings,
}

extension AppSectionLabel on AppSection {
  String get label {
    switch (this) {
      case AppSection.forYou: return 'For You';
      case AppSection.home: return 'Home';
      case AppSection.trending: return 'Trending';
      case AppSection.search: return 'Search';
      case AppSection.artists: return 'Artists';
      case AppSection.regions: return 'Regions';
      case AppSection.genres: return 'Genres';
      case AppSection.playlists: return 'Playlists';
      case AppSection.community: return 'Community';
      case AppSection.myProfile: return 'My Profile';
      case AppSection.upload: return 'Upload';
      case AppSection.discoverDJs: return 'Discover DJs';
      case AppSection.greatestOf: return 'Greatest Of';
      case AppSection.setBuilder: return 'Set Builder';
      case AppSection.aiCopilot: return 'AI Copilot';
      case AppSection.library: return 'My Library';
      case AppSection.duplicates: return 'Duplicates';
      case AppSection.savedCrates: return 'Saved Crates';
      case AppSection.watchlist: return 'Watchlist';
      case AppSection.exports: return 'Exports';
      case AppSection.settings: return 'Settings';
    }
  }
}
