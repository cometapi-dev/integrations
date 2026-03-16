#!/bin/bash
# Post-create: install a mock "openclaw" so the setup script passes pre-flight checks.
set -e

sudo tee /usr/local/bin/openclaw > /dev/null <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "openclaw 2026.3.8-codespace" ;;
  gateway)   echo "gateway ${2:-status}: ok (mock)" ;;
  onboard)   echo "onboard: ok (mock)" ;;
  models)    echo "models: ok (mock)" ;;
  *)         echo "openclaw mock: $*" ;;
esac
EOF
sudo chmod +x /usr/local/bin/openclaw
mkdir -p "$HOME/.openclaw"

echo ""
echo "✅ Dev environment ready!"
echo ""
echo "  bash openclaw/setup.sh --key sk-yourkey    # non-interactive"
echo "  bash openclaw/setup.sh                     # interactive prompt"
echo "  bash openclaw/tools/test_setup_cometapi.sh # full test suite"
echo ""
