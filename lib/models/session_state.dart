class SessionState {
  const SessionState({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.providerLabel,
    required this.isAuthenticated,
    required this.isDemo,
  });

  const SessionState.demo()
    : userId = 'demo-dj',
      displayName = 'Demo DJ',
      email = 'demo@viberadar.local',
      providerLabel = 'Demo workspace',
      isAuthenticated = false,
      isDemo = true;

  final String userId;
  final String displayName;
  final String email;
  final String providerLabel;
  final bool isAuthenticated;
  final bool isDemo;
}
