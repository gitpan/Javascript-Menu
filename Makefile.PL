use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'Javascript::Menu',
    'VERSION_FROM'	=> 'Menu.pm', 
    'PREREQ_PM'		=> {Tree::Numbered => 1.0, Tree::Numbered::DB => 1.0}, 
    ($] >= 5.005 ?    
      (AUTHOR     => 'Yosef Meller <mellerf@netvision.net.il>') : ()),
);
