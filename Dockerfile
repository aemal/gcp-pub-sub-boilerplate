# Use the official Bun image
FROM oven/bun:1 AS base
WORKDIR /usr/src/app

# Copy configuration files
COPY package.json bun.lockb ./
COPY config ./config

# Install dependencies
RUN bun install --frozen-lockfile

# Copy the rest of the application code
COPY . .

# Expose the port the app runs on
EXPOSE 3000

# Define the command to run the app
CMD ["bun", "run", "src/index.ts"] 