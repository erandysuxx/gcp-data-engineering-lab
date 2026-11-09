"""Punto de entrada del Flex Template (FLEX_TEMPLATE_PYTHON_PY_FILE)."""

import logging

from sellout_beam.pipeline import run

if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()
