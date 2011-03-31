#!/usr/bin/env python

# based on: http://www.jperla.com/blog/2007/09/26/capturing-frames-from-a-webcam-on-linux/

import Image
import sys

import opencv
#this is important for capturing/displaying images
from opencv import highgui 

camera = highgui.cvCreateCameraCapture(0)
def get_image():
    im = highgui.cvQueryFrame(camera)
    # Add the line below if you need it (Ubuntu 8.04+)
    #im = opencv.cvGetMat(im)
    #convert Ipl image to PIL image
    return opencv.adaptors.Ipl2PIL(im)

filename = sys.argv[1] 
image = get_image()
image.save(filename)

sys.exit(0)

