import os
import random
from pathlib import Path

import cocotb
from cocotb import start_soon
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, NextTimeStep, ReadOnly, RisingEdge, Timer
from cocotb_tools.runner import get_runner

@cocotb.test()
async def example_test(dut):
    pass


def test_arbiter_wrr_lock_hidden_runner():
    """Pytest wrapper."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "sources/arbiter_wrr_lock.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="arbiter_wrr_lock",
        always=True,
    )

    runner.test(
        hdl_toplevel="arbiter_wrr_lock",
        test_module="test_arbiter_wrr_lock_hidden", 
        waves=True 
    )
