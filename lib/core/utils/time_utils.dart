/// Time helpers. All timeline math uses integer microseconds to avoid
/// floating point drift between preview, subtitles and the FFmpeg command.
class TimeUtils {
  const TimeUtils._();

  static const int usPerSecond = 1000000;
  static const int usPerMillisecond = 1000;

  static Duration us(int microseconds) => Duration(microseconds: microseconds);

  static int toUs(Duration duration) => duration.inMicroseconds;

  /// `hh:mm:ss.mmm` (or `mm:ss.mmm` when hours are zero-free).
  static String timecode(
    Duration d, {
    bool withMillis = true,
    bool padHours = true,
  }) {
    final total = d.isNegative ? Duration.zero : d;
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);
    final seconds = total.inSeconds.remainder(60);
    final millis = total.inMilliseconds.remainder(1000);
    final h = padHours ? hours.toString().padLeft(2, '0') : '$hours';
    final base =
        '$h:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
    return withMillis ? '$base.${millis.toString().padLeft(3, '0')}' : base;
  }

  /// `1:04.2` style label used in chips and lists.
  static String compact(Duration d) {
    final total = d.isNegative ? Duration.zero : d;
    final minutes = total.inMinutes;
    final seconds = total.inSeconds.remainder(60);
    final tenths = total.inMilliseconds.remainder(1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  /// `00:00:01,250` for SRT payloads.
  static String srtTimestamp(Duration d) {
    final total = d.isNegative ? Duration.zero : d;
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);
    final seconds = total.inSeconds.remainder(60);
    final millis = total.inMilliseconds.remainder(1000);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')},'
        '${millis.toString().padLeft(3, '0')}';
  }

  /// `00:00:01.250` for WebVTT payloads.
  static String vttTimestamp(Duration d) =>
      srtTimestamp(d).replaceFirst(',', '.');

  /// `1.25` seconds for FFmpeg arguments.
  static String ffmpegSeconds(Duration d) {
    final seconds = d.inMicroseconds / TimeUtils.usPerSecond;
    return seconds.toStringAsFixed(3);
  }

  static String frames(Duration d, double fps) {
    final frame = (d.inMicroseconds * fps / TimeUtils.usPerSecond).round();
    return 'f$frame';
  }

  static final RegExp _timestampPattern = RegExp(
    r'^\s*(?:(\d{1,3}):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?\s*$',
  );

  /// Accepts `hh:mm:ss,mmm`, `mm:ss.mmm` and `ss.mmm`.
  static Duration? parseTimestamp(String raw) {
    final match = _timestampPattern.firstMatch(raw);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final fraction = match.group(4) ?? '';
    final millis = fraction.isEmpty
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  static Duration clamp(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static Duration parseOrZero(String? raw) =>
      parseTimestamp(raw ?? '') ?? Duration.zero;

  /// Rounds to a frame boundary so cut points stay deterministic.
  static int snapToFrame(int microseconds, double fps) {
    if (fps <= 0) return microseconds;
    final frameUs = usPerSecond / fps;
    return (microseconds / frameUs).round() * frameUs.round();
  }
}
