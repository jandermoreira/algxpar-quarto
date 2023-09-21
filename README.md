# algxpar-quarto
Extension to include `algxpar` pseudocode in Quarto documents

This extension is working minimally, which meets my current needs. It does not yet incorporate options or any fine tuning. I hope to add new features in the not too distant future.

## Concept
This extension embeds algorithms written in $\LaTeX$ into documents using the `algxpar` package. In HTML documents, the code block is compiled with `xelatex`, `pdflatex` or another compiler to a PDF and then converted to an SVG image, which is used in the document. For PDF documents, the code is simply entered and compiled directly.

## Dependencies
To use this extension you need:

* Quarto
* A $\LaTeX$ compiler
* The `algxpar` package from <https://ctan.org>, which requires:
  * algorithmicx (https://ctan.org/pkg/algorithmicx)
  * algpseudocode (https://ctan.org/pkg/algorithmicx)
  * amssymb (https://ctan.org/pkg/amsfonts)
  * fancyvrb (https://ctan.org/pkg/fancyvrb)
  * pgfmath (https://ctan.org/pkg/pgf)
  * pgfopts (https://ctan.org/pkg/pgf)
  * ragged2e (https://ctan.org/pkg/ragged2e)
  * tcolorbox (https://www.ctan.org/pkg/tcolorbox)
  * varwidth (https://www.ctan.org/pkg/varwidth)
  * xcolor (https://www.ctan.org/pkg/xcolor)
 
## Disclaimer
This extension is in a very early state of development and has not been tested beyond the minimum necessary.

## Licence
See [MIT License](LICENSE)
