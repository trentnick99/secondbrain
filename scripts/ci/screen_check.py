#!/usr/bin/env python3
"""Exit 0 when a screenshot should be retaken: it matches the Home shot or is still a blank launch screen.
Usage: screen_check.py <home.png> <shot.png>"""
import sys
from PIL import Image, ImageChops, ImageStat

home = Image.open(sys.argv[1]).convert("L").resize((201, 437))
shot = Image.open(sys.argv[2]).convert("L").resize((201, 437))
# Ignore the status bar, which is identical everywhere.
box = (0, 30, 201, 437)
home, shot = home.crop(box), shot.crop(box)
blank = ImageStat.Stat(shot).stddev[0] < 6
same_as_home = ImageStat.Stat(ImageChops.difference(home, shot)).mean[0] < 3
sys.exit(0 if blank or same_as_home else 1)
