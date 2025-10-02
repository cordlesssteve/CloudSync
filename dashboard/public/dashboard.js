/**
 * CloudSync Dashboard Frontend JavaScript
 * Handles real-time updates and user interactions
 */

class CloudSyncDashboard {
    constructor() {
        this.socket = null;
        this.isConnected = false;
        this.logs = [];
        this.activeSyncs = new Set();

        this.init();
    }

    init() {
        // Initialize Socket.IO connection
        this.socket = io();
        this.setupSocketListeners();

        // Setup event listeners
        this.setupEventListeners();

        // Load initial data
        this.loadInitialData();
    }

    setupSocketListeners() {
        this.socket.on('connect', () => {
            console.log('Connected to CloudSync server');
            this.updateConnectionStatus(true);
            this.isConnected = true;
        });

        this.socket.on('disconnect', () => {
            console.log('Disconnected from CloudSync server');
            this.updateConnectionStatus(false);
            this.isConnected = false;
        });

        this.socket.on('systemStatus', (status) => {
            console.log('Received system status:', status);
            this.updateSystemStatus(status);
        });

        this.socket.on('syncProgress', (data) => {
            this.handleSyncProgress(data);
        });

        this.socket.on('syncComplete', (data) => {
            this.handleSyncComplete(data);
        });
    }

    setupEventListeners() {
        // Auto-refresh every 30 seconds
        setInterval(() => {
            if (this.isConnected) {
                this.socket.emit('requestUpdate');
            }
        }, 30000);
    }

    async loadInitialData() {
        try {
            // Load logs
            await this.loadLogs('health');
        } catch (error) {
            console.error('Error loading initial data:', error);
        }
    }

    updateConnectionStatus(connected) {
        const statusDot = document.getElementById('statusDot');
        const statusText = document.getElementById('statusText');

        if (connected) {
            statusDot.className = 'status-dot online';
            statusText.textContent = 'Connected';
        } else {
            statusDot.className = 'status-dot offline';
            statusText.textContent = 'Disconnected';
        }
    }

    updateSystemStatus(status) {
        // Hide loading and show dashboard
        document.getElementById('loading').style.display = 'none';
        document.getElementById('dashboard').style.display = 'block';

        // Update health status
        if (status.health) {
            this.updateElement('rcloneStatus',
                status.health.rcloneConnectivity ? '✅ Online' : '❌ Offline');
            this.updateElement('diskUsage',
                status.health.diskUsage ? `${status.health.diskUsage}%` : 'Unknown');
            this.updateElement('conflictCount', status.health.conflicts || 0);
            this.updateElement('lastHealthCheck',
                this.formatTimestamp(status.health.lastCheck));

            // Update feature status
            if (status.health.features) {
                this.updateFeatureStatus('dedupeStatus', status.health.features.smartDeduplication);
                this.updateFeatureStatus('checksumStatus', status.health.features.checksumVerification);
                this.updateFeatureStatus('bisyncStatus', status.health.features.bidirectionalSync);
                this.updateFeatureStatus('conflictStatus', status.health.features.conflictResolution);
            }
        }

        // Update sync statistics
        if (status.stats) {
            this.updateElement('lastSync',
                status.stats.lastSync ? this.formatTimestamp(status.stats.lastSync) : 'Never');

            if (status.stats.lastBisync) {
                this.updateElement('filesToRemote', status.stats.lastBisync.files_copied_to_remote || 0);
                this.updateElement('filesToLocal', status.stats.lastBisync.files_copied_to_local || 0);
            }

            if (status.stats.features && status.stats.features['last-dedupe']) {
                this.updateElement('lastDedupe',
                    this.formatTimestamp(status.stats.features['last-dedupe']));
            }
        }

        // Update conflicts
        this.updateConflicts(status.conflicts || []);

        // Update last updated timestamp
        this.updateElement('lastUpdated', this.formatTimestamp(status.lastUpdate));
    }

    updateElement(id, content) {
        const element = document.getElementById(id);
        if (element) {
            element.textContent = content;
        }
    }

    updateFeatureStatus(elementId, isActive) {
        const element = document.getElementById(elementId);
        if (element) {
            element.className = `feature-status ${isActive ? 'active' : 'inactive'}`;
        }
    }

    updateConflicts(conflicts) {
        const conflictsCard = document.getElementById('conflictsCard');
        const conflictsList = document.getElementById('conflictsList');

        if (conflicts.length > 0) {
            conflictsCard.style.display = 'block';
            conflictsList.innerHTML = conflicts.map(conflict => `
                <div class="conflict-item">
                    <i class="fas fa-exclamation-triangle"></i>
                    <span>${conflict.file || conflict}</span>
                </div>
            `).join('');
        } else {
            conflictsCard.style.display = 'none';
        }
    }

    formatTimestamp(timestamp) {
        if (!timestamp) return 'Unknown';

        try {
            const date = new Date(timestamp);
            if (isNaN(date.getTime())) {
                return timestamp; // Return as-is if not a valid date
            }

            return date.toLocaleString();
        } catch (error) {
            return timestamp;
        }
    }

    handleSyncProgress(data) {
        this.activeSyncs.add(data.type);
        this.showSyncProgress(data.type);
        this.addLogMessage(data.output, data.error ? 'error' : 'info');
    }

    handleSyncComplete(data) {
        this.activeSyncs.delete(data.type);
        this.hideSyncProgress();
        this.addLogMessage(`Sync ${data.type} completed with exit code ${data.exitCode}`,
            data.exitCode === 0 ? 'success' : 'error');

        // Request status update after sync
        setTimeout(() => {
            this.socket.emit('requestUpdate');
        }, 1000);
    }

    showSyncProgress(type) {
        const progressElement = document.getElementById('syncProgress');
        const statusElement = document.getElementById('syncStatus');

        progressElement.style.display = 'block';
        statusElement.textContent = `Running ${type} sync...`;

        // Animate progress bar
        const progressFill = progressElement.querySelector('.progress-fill');
        progressFill.style.width = '60%';
    }

    hideSyncProgress() {
        const progressElement = document.getElementById('syncProgress');
        const progressFill = progressElement.querySelector('.progress-fill');

        progressFill.style.width = '100%';

        setTimeout(() => {
            progressElement.style.display = 'none';
            progressFill.style.width = '0%';
        }, 1000);
    }

    addLogMessage(message, type = 'info') {
        const logContainer = document.getElementById('logContainer');
        const timestamp = new Date().toLocaleTimeString();

        const logLine = document.createElement('div');
        logLine.className = `log-line ${type}`;
        logLine.textContent = `[${timestamp}] ${message}`;

        logContainer.appendChild(logLine);

        // Keep only last 100 log lines
        const logLines = logContainer.querySelectorAll('.log-line');
        if (logLines.length > 100) {
            logLines[0].remove();
        }

        // Auto-scroll to bottom
        logContainer.scrollTop = logContainer.scrollHeight;
    }

    async loadLogs(type = 'health', lines = 50) {
        try {
            const response = await fetch(`/api/logs/${type}?lines=${lines}`);
            const data = await response.json();

            const logContainer = document.getElementById('logContainer');
            logContainer.innerHTML = '';

            if (data.logs && data.logs.length > 0) {
                data.logs.forEach(line => {
                    if (line.trim()) {
                        this.addLogMessage(line, 'info');
                    }
                });
            } else {
                this.addLogMessage('No logs available', 'info');
            }
        } catch (error) {
            console.error('Error loading logs:', error);
            this.addLogMessage('Error loading logs', 'error');
        }
    }
}

// Global functions for button clicks

async function runSync(type, dryRun = false) {
    if (window.dashboard && window.dashboard.activeSyncs.has(type)) {
        alert(`${type} sync is already running`);
        return;
    }

    const options = {};

    // Add any additional options based on type
    if (type === 'bidirectional') {
        // Could add UI for additional bisync options
    }

    try {
        const response = await fetch('/api/sync', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                type,
                dryRun,
                options
            })
        });

        const result = await response.json();

        if (response.ok) {
            console.log(`${type} sync started:`, result);
            if (window.dashboard) {
                window.dashboard.addLogMessage(
                    `Started ${type} sync${dryRun ? ' (dry run)' : ''}`,
                    'success'
                );
            }
        } else {
            throw new Error(result.error || 'Unknown error');
        }
    } catch (error) {
        console.error('Error starting sync:', error);
        alert(`Error starting sync: ${error.message}`);
        if (window.dashboard) {
            window.dashboard.addLogMessage(`Error starting ${type} sync: ${error.message}`, 'error');
        }
    }
}

function refreshLogs() {
    if (window.dashboard) {
        window.dashboard.loadLogs('health');
    }
}

function clearLogs() {
    const logContainer = document.getElementById('logContainer');
    logContainer.innerHTML = '<div class="log-line">Logs cleared</div>';
}

// Initialize dashboard when page loads
document.addEventListener('DOMContentLoaded', () => {
    window.dashboard = new CloudSyncDashboard();
});