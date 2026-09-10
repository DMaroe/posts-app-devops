import os from 'os';
import express from 'express';
import morgan from 'morgan';
import { Pool } from 'pg';

console.log("starting backend app")

const PORT = process.env.PORT || 8081

const pool = new Pool({
    user: process.env.DB_USER || "foo-user",
    password: process.env.DB_PASSWORD || "secret-foo-password",
    host: process.env.DB_HOST || "localhost",

    port: 5432,
    database: 'posts',
    connectionTimeoutMillis: 2000,
})

pool.on("error", e => {
    console.error("pool error", e)
})

const app = express()

// set up our middlewares
app.use(express.json())
app.use(morgan("dev"))

// ROUTES
// status route
app.get(["/", "/status"], async (req, res, next) => {
    let db = false

    try {
        await pool.query("SELECT 1")
        db = true
    } catch (e) {
        console.error("cannot connect to db", e)
    }

    res.json({
        status: "OK",
        service: "backend",
        db: db ? "OK" : "ERROR",
        host: os.hostname()
    })
})


// list posts
app.get("/posts", async (req, res, next) => {
    const result = await pool.query("SELECT * from posts")

    res.send(result.rows)
})

// create post
app.post("/posts", async (req, res, next) => {
    const post = req.body;

    if (!post?.title) throw new Error("Post must have a title")

    const INSERT_QUERY = `
            INSERT INTO posts (title, content, parent_id) VALUES ($1, $2, $3) RETURNING *
        `
    const result = await pool.query(INSERT_QUERY, [post.title, post.content, post.parent_id]);
    const newPost = result.rows[0];

    res.send(newPost)
})

// get post
app.get("/posts/:postId", async (req, res, next) => {
    const result = await pool.query("SELECT * from posts WHERE id = $1 LIMIT 1", [req.params.postId])
    const [post] = result.rows;

    if (!post) {
        throw new Error("Could not find post")
    }
    res.send(result.rows[0])
})

// 500 handler
app.use((err, req, res, next) => {
    // work around JS Errors poor serialisation
    const errorData = {
        name: err.name,
        message: err.message,
        stack: err.stack,
        cause: err.cause,
    }

    res.status(500).json(errorData)
});

// start listening for requests
app.listen(PORT, err => {
    if (err) {
        console.error("could not start backend app", err)
        process.exit(1)
    }

    console.log(`backend app listening on port ${PORT}`)
})