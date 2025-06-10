#!/bin/bash

# Run the setup script in test mode
echo "=== RUNNING SETUP SCRIPT ==="
docker run --name setup-test --privileged \
  -v "$PWD:/git/dotfiles:ro" \
  -e CONTAINER_MODE=true \
  ubuntu:latest \
  bash -c "
    # Run the setup script
    bash /git/dotfiles/setup.sh
    
    echo ''
    echo '=== SETUP COMPLETE ==='
    echo 'Container is ready for interactive testing'
  "

# Check if the container ran successfully
if [ $? -eq 0 ]; then
    echo ""
    echo "=== SETUP COMPLETED SUCCESSFULLY ==="
    echo "Now starting interactive shell to verify configuration..."
    echo ""
    
    # Commit the container to save the state
    docker commit setup-test setup-test-complete
    
    # Remove the temporary container
    docker rm setup-test
    
    # Run interactive shell as the test user to verify everything works
    echo "Starting interactive shell as testuser..."
    docker run --rm -it --privileged \
      -v "$PWD:/git/dotfiles:ro" \
      setup-test-complete \
      bash -c "
        echo 'Switching to testuser shell...'
        echo 'You can now test:'
        echo '  - zsh (should be default shell)'
        echo '  - docker --version'
        echo '  - nvim --version'
        echo '  - rustc --version'
        echo '  - node --version (after: source ~/.nvm/nvm.sh)'
        echo '  - tmux'
        echo '  - ls -la ~ (check dotfiles)'
        echo ''
        echo 'Type \"exit\" to leave'
        su - testuser
      "
    
    # Clean up the committed image
    docker rmi setup-test-complete
else
    echo "Setup failed. Removing container..."
    docker rm -f setup-test 2>/dev/null
    exit 1
fi
