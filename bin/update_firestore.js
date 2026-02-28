#!/usr/bin/env node
/**
 * Firestore app_updates document frissítő script
 * 
 * Használat:
 *   node bin/update_firestore.js <version> <changelog> [forceUpdate] [platform]
 * 
 * Példa:
 *   node bin/update_firestore.js "1.0.31" "Bug fixes" false android
 * 
 * Előfeltétel: firebase login (Firebase CLI bejelentkezve)
 */

const { execSync } = require('child_process');
const https = require('https');

async function main() {
  const version = process.argv[2];
  const changelog = process.argv[3] || 'New release';
  const isForceUpdate = process.argv[4] === 'true';
  const platform = process.argv[5] || 'latest'; // android, ios, latest
  const projectId = 'flightdeck-v2';

  if (!version) {
    console.error('Usage: node bin/update_firestore.js <version> <changelog> [forceUpdate] [platform]');
    process.exit(1);
  }

  // Get access token from Firebase CLI config file
  let token;
  try {
    const path = require('path');
    const fs = require('fs');
    const os = require('os');

    // Firebase CLI stores config in different locations depending on version/OS
    const candidates = [
      path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json'),
      process.env.APPDATA ? path.join(process.env.APPDATA, 'configstore', 'firebase-tools.json') : null,
    ].filter(Boolean);

    let configDir = null;
    for (const c of candidates) {
      if (fs.existsSync(c)) { configDir = c; break; }
    }
    if (!configDir) {
      throw new Error(`Config file not found. Searched: ${candidates.join(', ')}`);
    }
    console.log(`[INFO] Using config: ${configDir}`);
    
    const config = JSON.parse(require('fs').readFileSync(configDir, 'utf8'));
    const refreshToken = config.tokens?.refresh_token;

    if (!refreshToken) {
      throw new Error('No refresh token found. Run: firebase login');
    }

    // Exchange refresh token for access token
    token = await getAccessToken(refreshToken);
  } catch (e) {
    console.error(`[ERROR] Failed to get Firebase token: ${e.message}`);
    console.error('        Run: firebase login');
    process.exit(1);
  }

  // Update Firestore document via REST API
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/app_updates/${platform}`;
  const body = JSON.stringify({
    fields: {
      version: { stringValue: version },
      changelog: { stringValue: changelog },
      isForceUpdate: { booleanValue: isForceUpdate },
      updatedAt: { stringValue: new Date().toISOString() },
    }
  });

  try {
    await httpRequest(url, 'PATCH', body, token);
    console.log(`[OK] Firestore updated: app_updates/${platform} -> version=${version}`);
  } catch (e) {
    console.error(`[ERROR] Firestore update failed: ${e.message}`);
    process.exit(1);
  }
}

function getAccessToken(refreshToken) {
  return new Promise((resolve, reject) => {
    const postData = `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}&client_id=563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com&client_secret=j9iVZfS8kkCEFUPaAeJV0sAi`;
    
    const options = {
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(postData),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.access_token) {
            resolve(json.access_token);
          } else {
            reject(new Error(json.error_description || 'Token exchange failed'));
          }
        } catch (e) {
          reject(new Error('Failed to parse token response'));
        }
      });
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

function httpRequest(url, method, body, token) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const options = {
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: method,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(data);
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

main();
