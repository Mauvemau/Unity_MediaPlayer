using System.Collections;
using UnityEngine;
using UnityEngine.Video;

public class TVController : MonoBehaviour
{
    [Header("Video Players")]
    [Tooltip("Reference to ALL active video players that need to be synced (e.g., CRT shader player, raw player, etc.).")]
    [SerializeField] private VideoPlayer[] _videoPlayers;

    [Header("Playlist")]
    [SerializeField] private VideoClip[] _playlist;
    [SerializeField] private int _currentIndex = 0;

    [Header("Controls State")]
    [SerializeField] private bool _loopCurrentVideo = false;
    private bool _isPaused = false;

    // Properties for external UI access if needed
    public bool LoopCurrentVideo => _loopCurrentVideo;
    public bool IsPaused => _isPaused;

    private void Start()
    {
        if (_videoPlayers == null || _videoPlayers.Length == 0)
        {
            Debug.LogWarning("CRTPlaylistController: No video players assigned!");
            return;
        }

        // Subscribe the master (first) video player to the end-of-video event
        _videoPlayers[0].loopPointReached += OnVideoFinished;

        // Start the first video if the playlist has items
        if (_playlist != null && _playlist.Length > 0)
        {
            PlayVideo(_currentIndex, false);
        }
    }

    private void OnDestroy()
    {
        if (_videoPlayers != null && _videoPlayers.Length > 0 && _videoPlayers[0] != null)
        {
            _videoPlayers[0].loopPointReached -= OnVideoFinished;
        }
    }

    private void Update()
    {
        // Continuously sync secondary players to the master player (_videoPlayers[0]) to prevent drift
        SyncAllPlayersTime();
    }

    /// <summary>
    /// Loads and plays a video at the specified index across all video players.
    /// </summary>
    public void PlayVideo(int index, bool zapping = false)
    {
        if (_playlist == null || _playlist.Length == 0) return;

        // Ensure looping wraps around the playlist cleanly
        _currentIndex = (index + _playlist.Length) % _playlist.Length;
        VideoClip clipToPlay = _playlist[_currentIndex];

        StartCoroutine(ConfigureAndPlayRoutine(clipToPlay, zapping));
    }

    private IEnumerator ConfigureAndPlayRoutine(VideoClip clip, bool zapping)
    {
        // 1. Assign clips and trigger preparation on ALL players
        foreach (var player in _videoPlayers)
        {
            if (player == null) continue;

            player.clip = clip;
            player.isLooping = false;
            player.Prepare();
        }

        // 2. Wait until EVERY video player in the array is fully prepared
        bool allPrepared = false;
        while (!allPrepared)
        {
            allPrepared = true;
            foreach (var player in _videoPlayers)
            {
                if (player != null && !player.isPrepared)
                {
                    allPrepared = false;
                    break;
                }
            }
            yield return null;
        }

        // 3. Calculate random target time if zapping
        double targetTime = 0.0;
        if (zapping && _videoPlayers[0] != null && _videoPlayers[0].length > 0)
        {
            float randomPercent = Random.Range(0.05f, 0.75f);
            targetTime = _videoPlayers[0].length * randomPercent;
        }

        // 4. Apply target time and play state to all players simultaneously
        foreach (var player in _videoPlayers)
        {
            if (player == null) continue;

            player.time = targetTime;

            if (!_isPaused)
            {
                player.Play();
            }
            else
            {
                player.Play();
                player.Pause(); // Ensures it stays paused on the exact zapped frame if pause is active
            }
        }
    }

    private void OnVideoFinished(VideoPlayer source)
    {
        if (_loopCurrentVideo)
        {
            // Replay current video from start
            PlayVideo(_currentIndex, false);
        }
        else
        {
            // Advance to the next video automatically (loops playlist)
            SkipForward();
        }
    }

    private void SyncAllPlayersTime()
    {
        if (_videoPlayers == null || _videoPlayers.Length < 2) return;
        if (!_videoPlayers[0].isPlaying || _isPaused) return;

        double masterTime = _videoPlayers[0].time;

        for (int i = 1; i < _videoPlayers.Length; i++)
        {
            if (_videoPlayers[i] == null || !_videoPlayers[i].isPlaying) continue;

            // If a player drifts by more than 50ms, snap it to the master time
            if (Mathf.Abs((float)(_videoPlayers[i].time - masterTime)) > 0.05f)
            {
                _videoPlayers[i].time = masterTime;
            }
        }
    }

    // ==========================================
    //              PUBLIC CONTROLS
    // ==========================================

    /// <summary>
    /// Toggles loop mode for the current playing video.
    /// </summary>
    public void ToggleLoop()
    {
        _loopCurrentVideo = !_loopCurrentVideo;
    }

    public void ToggleLoop(bool state)
    {
        _loopCurrentVideo = state;
    }

    /// <summary>
    /// Pauses or unpauses all video players on the exact same frame.
    /// </summary>
    public void TogglePause()
    {
        _isPaused = !_isPaused;

        foreach (var player in _videoPlayers)
        {
            if (player == null) continue;

            if (_isPaused)
            {
                player.Pause();
            }
            else
            {
                player.Play();
            }
        }
    }

    /// <summary>
    /// Seeks forward (+) or backward (-) by a given amount of seconds across all players.
    /// </summary>
    public void Seek(float seconds)
    {
        if (_videoPlayers == null || _videoPlayers[0] == null) return;

        double newTime = Mathf.Clamp((float)_videoPlayers[0].time + seconds, 0f, (float)_videoPlayers[0].length);

        foreach (var player in _videoPlayers)
        {
            if (player != null)
            {
                player.time = newTime;
            }
            player.Pause();
            player.Play();
        }
    }

    /// <summary>
    /// Skips to the next video in the playlist.
    /// </summary>
    public void SkipForward()
    {
        PlayVideo(_currentIndex + 1, false);
    }

    /// <summary>
    /// Skips to the previous video in the playlist.
    /// </summary>
    public void SkipBackward()
    {
        PlayVideo(_currentIndex - 1, false);
    }

    /// <summary>
    /// "Zapping" skip: Switches to the next video and jumps to a random point (5% - 75%).
    /// </summary>
    public void ZappingSkip()
    {
        PlayVideo(_currentIndex + 1, true);
    }
}