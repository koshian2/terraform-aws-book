"""Initialize ADOT before importing the MCP and boto3 (ZIP deployment entry point)."""
from opentelemetry.instrumentation.auto_instrumentation import initialize

initialize(swallow_exceptions=False)

from server import main

main()
