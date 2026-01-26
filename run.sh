#!/bin/bash
# Quick start script for HackTerm80s development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

show_help() {
    echo "HackTerm80s Development Helper"
    echo ""
    echo "Usage: ./run.sh [command]"
    echo ""
    echo "Commands:"
    echo "  dev         - Full rebuild: export game, restart API + web (USE THIS)"
    echo "  editor      - Launch Godot editor in Docker"
    echo "  play        - Run the game in Docker"
    echo "  build       - Build game for all platforms"
    echo "  web         - Build and serve web version on port 9080"
    echo "  multiplayer - Build web + start API server (full stack)"
    echo "  api         - Start only the API server on port 3000"
    echo "  players     - List all registered players"
    echo "  shell       - Open a shell in the container"
    echo "  clean       - Remove Docker images and builds"
    echo "  help        - Show this help"
    echo ""
}

setup_display() {
    # Allow Docker to connect to X server
    if command -v xhost &> /dev/null; then
        xhost +local:docker 2>/dev/null || true
    fi
}

case "${1:-help}" in
    editor)
        echo "Starting Godot Editor..."
        setup_display
        docker compose up --build godot-editor
        ;;
    play)
        echo "Running game..."
        setup_display
        docker compose --profile run up --build godot-run
        ;;
    build)
        echo "Building game..."
        mkdir -p builds
        docker compose --profile build up --build godot-build
        echo ""
        echo "Builds available in ./builds/"
        ls -la builds/ 2>/dev/null || echo "(no builds yet)"
        ;;
    web)
        echo "Building and serving web version..."
        mkdir -p builds/web
        
        # Stop existing container
        docker rm -f hackterm80s-game 2>/dev/null || true
        
        # Clean old build
        rm -rf builds/web/index.*
        
        # Export to HTML5
        echo "Exporting to HTML5..."
        docker run --rm \
            -v "$(pwd)/game:/game" \
            -v "$(pwd)/builds:/builds" \
            hackterm80s-godot-editor:latest \
            godot --headless --path /game --export-debug "HTML5" /builds/web/index.html
        
        # Build web container
        echo "Building web container..."
        cd builds/web
        docker build -t hackterm80s-web:latest .
        
        # Start web server
        echo "Starting web server..."
        docker run -d --name hackterm80s-game -p 9080:80 hackterm80s-web:latest
        
        echo ""
        echo "Game available at http://localhost:9080/"
        echo "Use 'docker logs hackterm80s-game' to view logs"
        echo "Use 'docker rm -f hackterm80s-game' to stop"
        ;;
    dev)
        echo "=== Full rebuild for development ==="
        mkdir -p builds/web server/db

        # Stop all containers
        echo "[1/4] Stopping containers..."
        docker compose --profile multiplayer down 2>/dev/null || true
        docker rm -f hackterm80s-game hackterm80s-web hackterm80s-api 2>/dev/null || true

        # Clean web build
        echo "[2/4] Cleaning old build..."
        rm -rf builds/web/index.*

        # Export game
        echo "[3/4] Exporting game..."
        docker run --rm \
            -v "$(pwd)/game:/game" \
            -v "$(pwd)/builds:/builds" \
            hackterm80s-godot-editor:latest \
            godot --headless --path /game --export-debug "HTML5" /builds/web/index.html

        # Start fresh containers
        echo "[4/4] Starting services..."
        docker compose --profile multiplayer up -d --build --force-recreate

        # Wait for API to be ready (with retries)
        echo ""
        echo "Waiting for API server..."
        for i in {1..30}; do
            API_STATUS=$(curl -s http://localhost:3000/api/status 2>/dev/null || echo "")
            if [[ "$API_STATUS" == *"online"* ]]; then
                echo "  API ready after ${i}s"
                break
            fi
            sleep 1
        done

        # Warmup API with OPTIONS preflight (fixes browser connection issue)
        curl -s -X OPTIONS -H "Origin: http://localhost:9080" -H "Access-Control-Request-Method: GET" http://localhost:3000/api/status >/dev/null 2>&1

        # Verify services
        API_STATUS=$(curl -s http://localhost:3000/api/status 2>/dev/null || echo "FAILED")
        WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/ 2>/dev/null || echo "FAILED")

        echo ""
        echo "========================================="
        echo "  HackTerm80s Dev Environment"
        echo "========================================="
        echo "  Game:  http://localhost:9080/ (HTTP $WEB_STATUS)"
        echo "  API:   http://localhost:3000/api/status"
        echo "         $API_STATUS"
        echo ""
        echo "  Rebuild: ./run.sh dev"
        echo "  Logs:    docker compose --profile multiplayer logs -f"
        echo "  Stop:    docker compose --profile multiplayer down"
        echo "========================================="
        ;;
    multiplayer)
        echo "Starting multiplayer stack (web + API)..."
        mkdir -p builds/web server/db

        # Stop existing containers
        docker rm -f hackterm80s-game hackterm80s-web hackterm80s-api 2>/dev/null || true

        # Clean and rebuild web export
        rm -rf builds/web/index.*
        echo "Exporting to HTML5..."
        docker run --rm \
            -v "$(pwd)/game:/game" \
            -v "$(pwd)/builds:/builds" \
            hackterm80s-godot-editor:latest \
            godot --headless --path /game --export-debug "HTML5" /builds/web/index.html

        # Start services with docker compose
        echo "Starting services..."
        docker compose --profile multiplayer up --build -d

        echo ""
        echo "========================================="
        echo "  HackTerm80s Multiplayer Stack"
        echo "========================================="
        echo "  Game:  http://localhost:9080/"
        echo "  API:   http://localhost:3000/api/status"
        echo ""
        echo "  Logs:  docker compose --profile multiplayer logs -f"
        echo "  Stop:  docker compose --profile multiplayer down"
        echo "========================================="
        ;;
    api)
        echo "Starting API server only..."
        mkdir -p server/db
        docker compose --profile multiplayer up --build -d hackterm-api
        echo ""
        echo "API server at http://localhost:3000/"
        echo "Use 'docker compose --profile multiplayer logs -f hackterm-api' for logs"
        ;;
    players)
        echo "Registered Players"
        echo "========================================="
        if [ -f "server/db/hackterm.db" ]; then
            docker run --rm -v "$(pwd)/server/db:/db" alpine:latest sh -c \
                'apk add --quiet sqlite && sqlite3 /db/hackterm.db "SELECT handle, phone_number, recovery_code, created_at FROM players ORDER BY created_at DESC;"' \
                | while IFS='|' read -r handle phone code created; do
                    printf "  %-12s  %-10s  %-18s  %s\n" "$handle" "$phone" "$code" "$created"
                done
            echo ""
            total=$(docker run --rm -v "$(pwd)/server/db:/db" alpine:latest sh -c \
                'apk add --quiet sqlite && sqlite3 /db/hackterm.db "SELECT COUNT(*) FROM players;"')
            echo "Total: $total players"
        else
            echo "  No database found. Start the API server first."
        fi
        echo "========================================="
        ;;
    shell)
        echo "Opening shell in container..."
        setup_display
        docker compose run --rm godot-editor /bin/bash
        ;;
    clean)
        echo "Cleaning up..."
        docker compose down --rmi local -v
        rm -rf builds/*
        echo "Done!"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
