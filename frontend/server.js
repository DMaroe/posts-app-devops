import os from 'os';
import axios from 'axios';
import express from 'express';
import expressLayouts from 'express-ejs-layouts';
import morgan from 'morgan';

console.log("starting frontend server")

const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:8080"
const PORT = process.env.PORT || 8081

const backendClient = axios.create({ baseURL: BACKEND_URL })

const app = express()

// ejs layouts middlewares
app.set('view engine', 'ejs');
app.use(expressLayouts)
app.set("layout", "layouts/main")

// parse requests with urlencoded bodies
app.use(express.urlencoded())

// set up a simple request logger
app.use(morgan("dev"))

// ROUTES
// status route
app.get("/status", async (req, res) => {
    res.json({
        status: "OK",
        service: "frontend"
    })
})

// render homepage
app.get("/", async (req, res) => {
    try {
        const statusResponse = await backendClient.get("/status")

        const backend = statusResponse.data?.status === "OK"
        const db = statusResponse.data?.db === "OK"

        res.render("pages/home", {
            backend,
            db,
            frontendHost: os.hostname(),
            backendHost: statusResponse.data?.host || "unknown",
        })
    } catch (e) {
        console.error("could not reach backend", e)
        res.render("pages/home", {
            backend: false,
            db: false,
            frontendHost: os.hostname(),
            backendHost: "unreachable",
        })
    }
})

// list posts
app.get("/posts", async (req, res) => {
    const postsResponse = await backendClient.get("/posts")

    res.render("pages/posts/list", { posts: postsResponse.data })
})

// list posts
app.get("/posts/new", async (req, res) => {
    const postsResponse = await backendClient.get("/posts")

    res.render("pages/posts/new", { posts: postsResponse.data })
})

// create post
app.post("/posts/new", async (req, res) => {
    const newPost = req.body;

    console.log({ newPost })

    const createPostResponse = await backendClient.post("/posts", newPost)

    res.redirect(`/posts/${createPostResponse.data.id}`)
})

// get post
app.get("/posts/:postId", async (req, res) => {
    const postResponse = await backendClient.get(`/posts/${req.params.postId}`)

    res.render("pages/posts/detail", { post: postResponse.data })
})

// 404 handler
app.use((req, res) => {
    res.status(404).render('pages/error', {
        title: 'Not Found',
        status: 404,
        message: 'This twittie doesn\'t exist',
        details: `The requested URL ${req.originalUrl} was not found on this server.`,
    });
});

// 500 handler
app.use((err, req, res, next) => {
    const error = err.response?.data || err
    res.status(500).render('pages/error', {
        title: 'Server Error',
        status: 500,
        message: 'Internal Server Error',
        details: error.message,
    });
});

// start listening for requests
app.listen(PORT, (err) => {
    if (err) {
        console.error("could not start frontend server", err)
        process.exit(1)
    }

    console.log(`frontend server listening on port ${PORT}`)
})