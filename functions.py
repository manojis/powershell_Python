import fileinput
import subprocess
import sys
import os
from time import strftime

def replaceVal(filename,  origstr, replacestr):
    f = fileinput.input(filename, inplace=1, backup='_'+strftime("%Y%m%d%H%M%S"))
    for line in f:
        line = line.replace(origstr,replacestr)
        print line,
    f.close()
    return;
	
def updateValByStartsWith(filename,  startswith, begin, end, replacestr):
    f = fileinput.input(filename, inplace=1)
    for line in f:
        if line.startswith(startswith, begin, end):
            print replacestr
        else:
            print line,
    f.close()
    return;

def updateValByKey(filename, key, replaceval):
    f = fileinput.input(filename, inplace=1)
    for line in f:
        if line.startswith(key):
            print key + replaceval
        else:
            print line,
    f.close()
    return;
