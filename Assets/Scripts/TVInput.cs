using System;
using UnityEngine;

public class TVInput : MonoBehaviour {
    [Header("Input Keys")]
    [SerializeField] private KeyCode pauseButton = KeyCode.Space;
    [SerializeField] private KeyCode loopButton = KeyCode.L;
    [SerializeField] private KeyCode seekForwardButton = KeyCode.RightArrow;
    [SerializeField] private KeyCode seekBackButton = KeyCode.LeftArrow;
    [SerializeField] private KeyCode skipForwardButton = KeyCode.E;
    [SerializeField] private KeyCode skipBackButton = KeyCode.Q;
    [SerializeField] private KeyCode zapButton = KeyCode.Z;

    [Header("Settings")] 
    [SerializeField] private float seekTimeInSeconds = 10f;
    
    private TVController _tvController;

    private void Awake() {
        _tvController = GetComponent<TVController>();
    }

    private void Update() {
        if (Input.GetKeyDown(pauseButton)) {
            _tvController.TogglePause();
        }
        if (Input.GetKeyDown(loopButton)) {
            _tvController.ToggleLoop();
        }
        if (Input.GetKeyDown(seekForwardButton)) {
            _tvController.Seek(seekTimeInSeconds);
        }
        if (Input.GetKeyDown(seekBackButton)) {
            _tvController.Seek(-seekTimeInSeconds);
        }
        if (Input.GetKeyDown(skipForwardButton)) {
            _tvController.SkipForward();
        }
        if (Input.GetKeyDown(skipBackButton)) {
            _tvController.SkipBackward();
        }
        if (Input.GetKeyDown(zapButton)) {
            _tvController.ZappingSkip();
        }
    }
}
