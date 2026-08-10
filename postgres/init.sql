-- Enable the pageinspect extension which allows us to inspect database page contents directly.
CREATE EXTENSION IF NOT EXISTS pageinspect;

-- Create a basic table to use for our Module 1 storage internals lab.
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50),
    email VARCHAR(100)
);

-- Prepopulate with one row so we can look at it immediately.
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
