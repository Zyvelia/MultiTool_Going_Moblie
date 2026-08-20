enum BrickBreakerMode {
  endless,
  siege,
}

extension BrickBreakerModeInfo on BrickBreakerMode {
  String get title {
    switch (this) {
      case BrickBreakerMode.endless:
        return 'Endless';
      case BrickBreakerMode.siege:
        return 'Siege';
    }
  }

  String get subtitle {
    switch (this) {
      case BrickBreakerMode.endless:
        return 'Classic waves — clear the board when you can.';
      case BrickBreakerMode.siege:
        return 'The wall keeps creeping — fight it before it reaches you.';
    }
  }

  String get icon {
    switch (this) {
      case BrickBreakerMode.endless:
        return '∞';
      case BrickBreakerMode.siege:
        return '⚔';
    }
  }

  String get highScoreKey {
    switch (this) {
      case BrickBreakerMode.endless:
        return 'zs_brick_breaker_high_score';
      case BrickBreakerMode.siege:
        return 'zs_brick_breaker_high_score_siege';
    }
  }

  String get progressSaveKey {
    switch (this) {
      case BrickBreakerMode.endless:
        return 'zs_brick_breaker_save';
      case BrickBreakerMode.siege:
        return 'zs_brick_breaker_save_siege';
    }
  }
}
