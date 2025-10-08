const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const AWS = require('aws-sdk');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// AWS Configuration
AWS.config.update({ region: process.env.AWS_REGION || 'us-east-1' });
const sqs = new AWS.SQS();
const sns = new AWS.SNS();
const s3 = new AWS.S3();
const secretsManager = new AWS.SecretsManager();

// Database connection pool
let dbPool = null;

// Middleware
app.use(helmet());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Initialize database connection
async function initializeDatabase() {
  try {
    if (process.env.DB_SECRET_ARN) {
      // Fetch database credentials from Secrets Manager
      const secretValue = await secretsManager.getSecretValue({
        SecretId: process.env.DB_SECRET_ARN
      }).promise();

      const secret = JSON.parse(secretValue.SecretString);

      dbPool = new Pool({
        host: secret.host,
        port: secret.port,
        database: secret.dbname,
        user: secret.username,
        password: secret.password,
        max: 20,
        idleTimeoutMillis: 30000,
        connectionTimeoutMillis: 2000,
      });

      console.log('Database connection pool initialized');
    } else {
      console.log('No DB_SECRET_ARN provided, skipping database initialization');
    }
  } catch (error) {
    console.error('Error initializing database:', error);
  }
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    environment: process.env.ENVIRONMENT || 'unknown',
    version: process.env.APP_VERSION || '1.0.0'
  });
});

// Readiness check endpoint
app.get('/ready', async (req, res) => {
  try {
    if (dbPool) {
      await dbPool.query('SELECT 1');
    }
    res.status(200).json({
      status: 'ready',
      database: dbPool ? 'connected' : 'not configured'
    });
  } catch (error) {
    res.status(503).json({
      status: 'not ready',
      error: error.message
    });
  }
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'AWS DevOps Portfolio Application',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      ready: '/ready',
      items: '/api/items',
      queue: '/api/queue',
      storage: '/api/storage'
    }
  });
});

// API: Get all items from database
app.get('/api/items', async (req, res) => {
  try {
    if (!dbPool) {
      return res.status(503).json({ error: 'Database not configured' });
    }

    const result = await dbPool.query('SELECT * FROM items ORDER BY created_at DESC LIMIT 100');
    res.json({
      count: result.rows.length,
      items: result.rows
    });
  } catch (error) {
    console.error('Error fetching items:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// API: Create a new item
app.post('/api/items', async (req, res) => {
  try {
    if (!dbPool) {
      return res.status(503).json({ error: 'Database not configured' });
    }

    const { name, description } = req.body;

    if (!name) {
      return res.status(400).json({ error: 'Name is required' });
    }

    const result = await dbPool.query(
      'INSERT INTO items (name, description, created_at) VALUES ($1, $2, NOW()) RETURNING *',
      [name, description]
    );

    // Send message to SQS for async processing
    if (process.env.SQS_QUEUE_URL) {
      await sqs.sendMessage({
        QueueUrl: process.env.SQS_QUEUE_URL,
        MessageBody: JSON.stringify({
          action: 'item_created',
          item: result.rows[0]
        })
      }).promise();
    }

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating item:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// API: Send message to queue
app.post('/api/queue', async (req, res) => {
  try {
    if (!process.env.SQS_QUEUE_URL) {
      return res.status(503).json({ error: 'Queue not configured' });
    }

    const { message } = req.body;

    if (!message) {
      return res.status(400).json({ error: 'Message is required' });
    }

    const result = await sqs.sendMessage({
      QueueUrl: process.env.SQS_QUEUE_URL,
      MessageBody: JSON.stringify({
        message,
        timestamp: new Date().toISOString()
      })
    }).promise();

    res.status(200).json({
      success: true,
      messageId: result.MessageId
    });
  } catch (error) {
    console.error('Error sending message to queue:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// API: Upload to S3
app.post('/api/storage', async (req, res) => {
  try {
    if (!process.env.S3_BUCKET_NAME) {
      return res.status(503).json({ error: 'Storage not configured' });
    }

    const { filename, content } = req.body;

    if (!filename || !content) {
      return res.status(400).json({ error: 'Filename and content are required' });
    }

    const key = `uploads/${Date.now()}-${filename}`;

    await s3.putObject({
      Bucket: process.env.S3_BUCKET_NAME,
      Key: key,
      Body: content,
      ContentType: 'text/plain'
    }).promise();

    res.status(200).json({
      success: true,
      key,
      bucket: process.env.S3_BUCKET_NAME
    });
  } catch (error) {
    console.error('Error uploading to S3:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing server...');
  if (dbPool) {
    await dbPool.end();
  }
  process.exit(0);
});

// Start server
async function startServer() {
  await initializeDatabase();

  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Environment: ${process.env.ENVIRONMENT || 'development'}`);
  });
}

startServer();

module.exports = app;
