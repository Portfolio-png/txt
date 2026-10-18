'use strict';

// ---------------------------------------------------------------------------
// Dev tool — where the in-app marker's marks land.
//
// The app cannot write them itself. A Flutter macOS build is sandboxed
// (com.apple.security.app-sandbox), so its $HOME is a container under
// ~/Library/Containers/<bundle>/Data and a path like ~/.paper/marks.jsonl
// resolves somewhere nobody will find and, as it turned out, could not be
// written to at all. The backend is an ordinary process in the repo, so it
// writes the file where both the person marking and whoever reads the marks
// afterwards can actually get at it: <repo>/.paper-marks.jsonl
//
// Registered only outside production. It takes arbitrary text from a client
// and appends it to a file, which is exactly the sort of thing that has no
// business existing on a real deployment.
// ---------------------------------------------------------------------------

const fs = require('fs');
const path = require('path');

// Overridable so a test does not append to the repo's own marks.
const MARKS_PATH =
  process.env.PAPER_MARKS_FILE ||
  path.join(__dirname, '..', '..', '..', '.paper-marks.jsonl');

module.exports = function registerDevMarksRoutes({ app }) {
  if (process.env.NODE_ENV === 'production') return { marksPath: null };

  app.post('/api/dev/marks', (req, res) => {
    try {
      const marks = Array.isArray(req.body?.marks) ? req.body.marks : [req.body];
      const lines = marks
        .filter((mark) => mark && typeof mark === 'object')
        .map((mark) => JSON.stringify(mark))
        .join('\n');
      if (!lines) {
        return res.status(400).json({ success: false, error: 'No marks in body.' });
      }
      fs.appendFileSync(MARKS_PATH, `${lines}\n`);
      res.json({ success: true, path: MARKS_PATH });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/dev/marks', (req, res) => {
    try {
      const text = fs.existsSync(MARKS_PATH)
        ? fs.readFileSync(MARKS_PATH, 'utf8')
        : '';
      const marks = text
        .split('\n')
        .filter((line) => line.trim())
        .map((line) => {
          try {
            return JSON.parse(line);
          } catch (_) {
            return null;
          }
        })
        .filter(Boolean);
      res.json({ success: true, path: MARKS_PATH, marks });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/dev/marks', (req, res) => {
    try {
      if (fs.existsSync(MARKS_PATH)) fs.unlinkSync(MARKS_PATH);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`[devtools] marks -> ${MARKS_PATH}`);
  return { marksPath: MARKS_PATH };
};
