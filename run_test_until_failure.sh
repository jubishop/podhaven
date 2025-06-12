#!/bin/bash

# Script to run loadingFailureClearsTheDeck test repeatedly until failure
# Captures logs for both passing and failing runs

TEST_NAME="ParallelTests/PlayManagerTests/loadingFailureClearsTheDeck"
LOG_DIR="test_logs_$(date +%Y%m%d_%H%M%S)"
PASS_COUNT=0

# Create log directory
mkdir -p "$LOG_DIR"

echo "Running test repeatedly until failure..."
echo "Logs will be saved to: $LOG_DIR"
echo "Test: $TEST_NAME"
echo ""

while true; do
    PASS_COUNT=$((PASS_COUNT + 1))
    LOG_FILE="$LOG_DIR/run_${PASS_COUNT}.log"
    
    echo "Run #$PASS_COUNT - $(date)"
    
    # Run the test and capture all output
    xcodebuild test \
        -project PodHaven.xcodeproj \
        -scheme PodHaven \
        -testPlan PodHaven \
        -only-testing:"$TEST_NAME" \
        -quiet \
        > "$LOG_FILE" 2>&1
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "  ✓ PASS (saved to run_${PASS_COUNT}.log)"
        # Keep the passing log for comparison
        mv "$LOG_FILE" "$LOG_DIR/pass_run_${PASS_COUNT}.log"
    else
        echo "  ✗ FAIL after $PASS_COUNT attempts!"
        echo "  Failure log saved to: $LOG_FILE"
        mv "$LOG_FILE" "$LOG_DIR/FAILURE_run_${PASS_COUNT}.log"
        
        echo ""
        echo "=== FAILURE DETECTED ==="
        echo "Test failed on attempt #$PASS_COUNT"
        echo "Logs saved in: $LOG_DIR/"
        echo ""
        echo "Compare the failure log with a passing log:"
        echo "  Failure: $LOG_DIR/FAILURE_run_${PASS_COUNT}.log"
        
        # Find the most recent passing log
        LAST_PASS=$(find "$LOG_DIR" -name "pass_run_*.log" | sort -V | tail -1)
        if [ -n "$LAST_PASS" ]; then
            echo "  Last pass: $LAST_PASS"
            echo ""
            echo "To compare:"
            echo "  diff \"$LAST_PASS\" \"$LOG_DIR/FAILURE_run_${PASS_COUNT}.log\""
        fi
        
        echo ""
        echo "Failure log preview:"
        echo "===================="
        tail -20 "$LOG_DIR/FAILURE_run_${PASS_COUNT}.log"
        
        break
    fi
    
    # Brief pause between runs
    sleep 0.1
done

echo ""
echo "Script completed. Check $LOG_DIR/ for all logs."