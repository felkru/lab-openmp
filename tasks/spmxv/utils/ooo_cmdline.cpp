#include "ooo_cmdline.h"
#include <math.h>
#include <algorithm>
#include <vector>

#define RES_SMALL 229.045069
#define RES_LARGE 469.041944

#define SIZE_SMALL 59319
#define SIZE_LARGE 493039

void print_performance_results(ooo_options *tOptions, double t1, double t2, timespan *timings, ooo_input *tInput)
{
	// compute metrics
	double dTotalExperimentTime = t2 - t1;
	double dMinTime = numeric_limits<double>::max();
	double dMaxTime = numeric_limits<double>::min();
	double dMeanTime = 0.0;
	for (int i = 0; i < tOptions->iNumRepetitions; i++)
	{
		double d = timings[i].dEnd - timings[i].dBegin;
		dMinTime = std::min<double>(dMinTime, d);
		dMaxTime = std::max<double>(dMaxTime, d);
		dMeanTime += d;
	}
	dMeanTime /= tOptions->iNumRepetitions;

	double temp = (double)tInput->stNumNonzeros / 1e6 * 2.; // number of instructions in MFlop
	double mTotalFlops = tOptions->iNumRepetitions / dTotalExperimentTime * temp;
	double mMinFlops = temp / dMaxTime;
	double mMaxFlops = temp / dMinTime;
	double mMeanFlops = temp / dMeanTime;

	// print results
	std::cout << std::endl;
	std::cout << "Configuration              " << std::endl;
	std::cout << "Number of Threads:         " << tOptions->iNumThreads << std::endl;
	std::cout << "Number of Repetitions:     " << tOptions->iNumRepetitions << std::endl;
	std::cout << "Input filename:            " << tOptions->strFilename << std::endl;
	std::cout << std::endl;
	std::cout << "Time measurements          " << std::endl;
	std::cout << "Total experiment time:     " << dTotalExperimentTime << std::endl;
	std::cout << "Minimum kernel time:       " << dMinTime << std::endl;
	std::cout << "Maximum kernel time:       " << dMaxTime << std::endl;
	std::cout << "Arithm. Mean kernel time:  " << dMeanTime << std::endl;
	std::cout << std::endl;
	std::cout << "Performance results        " << std::endl;
	std::cout << "Total MFlops/s:            " << mTotalFlops << std::endl;
	std::cout << "Minimum MFlops/s:          " << mMinFlops << std::endl;
	std::cout << "Maximum MFlops/s:          " << mMaxFlops << std::endl;
	std::cout << "Arithm. Mean MFlops/s:     " << mMeanFlops << std::endl;
	std::cout << std::endl;
}

bool parseCmdLine(ooo_options *options, int argc, char* argv[])
{
	AnyOption *opt = new AnyOption();

	// set usage help text
	opt->addUsage("");
	opt->addUsage("Usage:");
	opt->addUsage("");
	opt->addUsage(" -h  --help:                 Prints this help text.");
	opt->addUsage(" -t  --threads num:          Number of threads to be used.");
	opt->addUsage(" -f  --filename name:        Use input file (default: none).");
	opt->addUsage(" -r  --repetitions num:      Number of repetitions (default: 10).");
	opt->addUsage(" -m  --matrix-format csr|ep: Sparse matrix format (Compressed sparse row(csr), Ellpack(ep)) (default: csr).");
	opt->addUsage(" -c  --create-matrix:        Create new sparse matrix. Cannot be used with filename option.");
	opt->addUsage(" -n  --num-rows num:         Number of rows (and columns) in created matrix (default: 1000) (only works with -c).");
	opt->addUsage(" -q  --shift-prob num:       Probability of nonzero moves in created matrix (default: 0.0) (only works with -c).");
	opt->addUsage(" -z  --num-row-nz num:       Number of nonzeros per row in created matrix (default: 5) (only works with -c).");
	opt->addUsage(" -w  --write-mat:            Write created matrix to file input-matrix/testMat.txt (only works with -c).");
	opt->addUsage("");
	opt->addUsage("");


	// set options and flags
	opt->setFlag("help", 'h');
	opt->setOption("threads", 't');
	opt->setOption("filename", 'f');
	opt->setOption("repetitions", 'r');
	opt->setOption("matrix-format", 'm');
	opt->setFlag("create-matrix", 'c');
	opt->setOption("num-rows", 'n');
	opt->setOption("shift-prob", 'q');
	opt->setOption("num-row-nz", 'z');
	opt->setFlag("write-mat", 'w');
	

	// process commandline
	opt->processCommandArgs(argc, argv);
	if (! opt->hasOptions())
	{
		opt->printUsage();
		delete opt;
		return false;
	}

	// get the values
	if (opt->getFlag("help") || opt->getFlag('h'))
	{
		opt->printUsage();
		delete opt;
		return false;
	}
	if (opt->getValue("threads") != NULL || opt->getValue('t') != NULL)
	{
		char *strNumThreads = opt->getValue('t');
		options->iNumThreads = atoi(strNumThreads);
	}
	else
	{
		opt->printUsage();
		delete opt;
		return false;
	}
	if (opt->getValue("filename") != NULL || opt->getValue('f') != NULL)
	{
		options->strFilename = opt->getValue('f');
		if (opt->getValue('c') != NULL ||
			opt->getValue('n') != NULL ||
			opt->getValue('q') != NULL ||
			opt->getValue('z') != NULL ||
			opt->getValue('w') != NULL)
		{
			std::cout << "filename option set, ignoring flags -c, -n, -q, -z, -w\n";
		}
		options->createMat = false;
	}
	else
	{
		if(opt->getFlag('c'))
		{
			options->createMat = true;
			if(opt->getValue('n') != NULL)
			{
				options->nRows = atoi(opt->getValue('n'));
			}
			else
			{
				options->nRows = 1000;
			}

			if(opt->getValue('q') != NULL)
			{
				options->q = atof(opt->getValue('q'));
			}
			else
			{
				options->q = 0.0;
			}

			if(opt->getValue('z') != NULL)
			{
				options->nzPerRow = atoi(opt->getValue('z'));
			}
			else
			{
				options->nzPerRow = 5;
			}
			options->writeMat = opt->getFlag('w');
		}
		else
		{
			std::cerr << "ERROR: input filename or -c flag required for this experiment!" << std::endl;
			std::cout << std::endl;
			delete opt;
			return false;
		}
	}
	if (opt->getValue("repetitions") != NULL || opt->getValue('r') != NULL)
	{
		char *strNumRepetitions = opt->getValue('r');
		int iNumRepetitions = atoi(strNumRepetitions);
		if (iNumRepetitions <= 0)
		{
			opt->printUsage();
			delete opt;
			return false;
		}
		options->iNumRepetitions = iNumRepetitions;
	}
	else
	{
		options->iNumRepetitions = 10;
	}
	if(opt->getValue("matrix-format") != NULL || opt->getValue('m') != NULL)
	{
		char *strMFormat = opt->getValue('m');
		if(strcmp(strMFormat, "csr") == 0) options->mformat = MFORMAT_CSR;
		else if(strcmp(strMFormat, "ep") == 0) options->mformat = MFORMAT_ELLPACK;

		else
		{
			std::cerr << "ERROR: unrecognized matrix format: " << strMFormat << std::endl;
			return false;
		}
	} 
	else
	{
		options->mformat = MFORMAT_CSR;
	}

	// done
	delete opt;
	return true;
}

bool loadInputFile_4SMXV(ooo_options *tOptions, ooo_input *tInput)
{
	// open file
	std::ifstream fdat(tOptions->strFilename.c_str(), std::fstream::binary);
	if (! fdat)
	{
		std::cerr << "ERROR: could not open input filename: " << tOptions->strFilename << std::endl;
		std::cout << std::endl;
		return false;
	}

	int iDummy;
	load_drops_matlab_matrix<double, int>(tOptions->strFilename.c_str(),
		tInput->row, tInput->col, tInput->val, tInput->stNumRows, iDummy,
		tInput->stNumNonzeros);

	return true;
}

// create random x vector
void randomRHS(ooo_input *tInput) 
{
	srand(42);
	tInput->x = new double[tInput->stNumRows];
	for(int i = 0; i < tInput->stNumRows; ++i) 
	{
		tInput->x[i] = (double)rand() / (double)RAND_MAX;
	}
}

// create random square Matrix of given size, diagonal structured with the probability q
void createMatrix(ooo_options *tOptions, ooo_input* tInput) 
{
	srand(42);

	tInput->stNumRows = tOptions->nRows;
	tInput->stNumNonzeros = tOptions->nzPerRow * tOptions->nRows;
	tInput->val = new double[tInput->stNumNonzeros];
	tInput->col = new int[tInput->stNumNonzeros];
	tInput->row = new int[tInput->stNumRows+1];
	
	// temporary column vector per row
	std::vector<int> cols;
	cols.resize(tOptions->nzPerRow);

	int nz = 0;
	for(int i = 0; i < tOptions->nRows; i++) 
	{
		tInput->row[i] = nz;

		for(int j = 0; j < tOptions->nzPerRow; j++)
		{
			int c = i + j - tOptions->nzPerRow/2;
			if(c < 0)
			{
				cols[j] = -1;
			}
			else if(c >= tInput->stNumRows)
			{
				cols[j] = tInput->stNumRows;
			}
			else
			{
				cols[j] = c;
			}

			// move value to random column with probability q
			if((double)rand() / (double)RAND_MAX < tOptions->q) {
				int newCol = rand() % tInput->stNumRows;
				// prevent the same column twice
				while(std::find(cols.begin(), cols.end(), newCol) != cols.end())
				{
					newCol = rand() % tInput->stNumRows;
				}
				cols[j] = newCol;
			}
		}

		// sort cols
		std::sort(cols.begin(), cols.end());

		for(int j = 0; j < tOptions->nzPerRow; j++) 
		{
			// random double value between 0 and 1
			tInput->val[nz] = (double)rand() / (double)RAND_MAX;

			// continue if column was out of bounds
			if(cols[j] == -1 || cols[j] == tInput->stNumRows) continue;

			tInput->col[nz] = cols[j];
			nz++;
		}
	}
	
	tInput->stNumNonzeros = nz;
	tInput->row[tInput->stNumRows] = tInput->stNumNonzeros;

	if(tOptions->writeMat) writeMatrix(tInput);
}

// write matrix to file
void writeMatrix(ooo_input* tInput) {
	FILE* fp = fopen("input-matrix/testMat.txt", "w");
	fprintf(fp, "%% %dx%d %d nonzeros\n", tInput->stNumRows, tInput->stNumRows, tInput->stNumNonzeros);

	for (int i = 0; i < tInput->stNumRows; i++)
	{
		int rowbeg = tInput->row[i];
		int rowend = tInput->row[i+1];
		int nz;
		for (nz = rowbeg; nz < rowend; nz++)
		{
			fprintf(fp, "%d %d %lf\n", i+1, tInput->col[nz] + 1, tInput->val[nz]);
		}
	}
	fclose(fp);
}

// checks if the MXV is done correctly by computing the sum of all elements in the result vector
void print_error_check(double *result, ooo_input *tInput)
{
	printf("\nCorrectness check\n");
	
	// determine correct result for input matrix
	double errorMargin = 0.000001;

	double total = 0.0;
	for (int i = 0; i < tInput->stNumRows; i++)
	{
		total += result[i];
	}

	switch (tInput->stNumRows) {
	case SIZE_SMALL:
		if(fabs(total - RES_SMALL) > errorMargin) {
			printf("Incorrect result! Error in computation.\n");
			return;
		}
		break;
	case SIZE_LARGE:
		if(fabs(total - RES_LARGE) > errorMargin) {
			printf("Incorrect result! Error in computation.\n");
			return;
		}
		break;
	default:
		printf("unknown matrix, skipping correctness check\n");
		return;
	}

	printf("Success, correct result.\n");
}

