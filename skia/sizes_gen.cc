#include <iostream>
#include <fstream>
#include <include/core/SkPaint.h>
#include <include/core/SkImageInfo.h>

int main() {
std::ofstream out("sizes.txt");
if (!out.is_open()) {std::cout << "unable to open file"; return 1;}
out << "SkPaint" << " " << sizeof(SkPaint) << "\n";
out << "SkImageInfo" << " " << sizeof(SkImageInfo) << "\n";
out.close();
return 0;}
