use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'Javascript::Menu',
    'VERSION_FROM'	=> 'Menu.pm', 
    'PREREQ_PM'		=> {NumberedTree => 1.0, NumberedTree::DBTree => 1.0}, 
    ($] >= 5.005 ?    
      (AUTHOR     => 'Yosef Meller <mellerf@netvision.net.il>') : ()),
);
